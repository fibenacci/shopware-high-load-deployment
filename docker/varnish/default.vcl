vcl 4.1;
# =============================================================================
# Shopware 6 VCL — based on Shopware's official sample.
#
# https://developer.shopware.com/docs/guides/hosting/performance/reverse-http-cache.html
#
# Two trust contracts with the backend:
#   1. Shopware sets X-Shopware-Allow-Nocache: 1 on responses that MUST NOT
#      be cached (cart, checkout, account, admin). We respect that.
#   2. Shopware fires HTTP PURGE / BAN requests from the kernel to invalidate
#      specific URLs (product detail change, theme:compile, ...). We accept
#      those only from the in-cluster ACL.
# =============================================================================

import std;
import vary;

backend default {
    .host = "__BACKEND_HOST__";
    .port = "__BACKEND_PORT__";
    .first_byte_timeout    = 300s;
    .between_bytes_timeout = 300s;
    .connect_timeout       = 10s;
    .probe = {
        .url = "/health";
        .timeout = 2s;
        .interval = 5s;
        .window = 3;
        .threshold = 2;
    }
}

# Trusted purgers — only in-cluster Shopware pods may purge.
# Kubernetes injects pod CIDRs; widen as needed via Helm/Kustomize patch.
acl purgers {
    "127.0.0.1";
    "10.0.0.0"/8;
    "172.16.0.0"/12;
    "192.168.0.0"/16;
}

sub vcl_recv {
    # --- PURGE / BAN ---------------------------------------------------
    if (req.method == "PURGE") {
        if (!client.ip ~ purgers) {
            return (synth(405, "PURGE not allowed from " + client.ip));
        }
        return (purge);
    }
    if (req.method == "BAN") {
        if (!client.ip ~ purgers) {
            return (synth(405, "BAN not allowed from " + client.ip));
        }
        if (req.http.X-Invalidation-Pattern) {
            ban("obj.http.X-Cache-Tags ~ " + req.http.X-Invalidation-Pattern);
            return (synth(200, "Banned"));
        }
        return (synth(400, "X-Invalidation-Pattern header required"));
    }

    # --- Methods we cache ----------------------------------------------
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    # --- Bypass list — never even ask Varnish to cache these. -----------
    # Admin panel, store-api auth, customer flows, payment callbacks.
    if (
        req.url ~ "^/admin"            ||
        req.url ~ "^/api/"             ||
        req.url ~ "^/store-api/"       ||
        req.url ~ "^/account"          ||
        req.url ~ "^/checkout"         ||
        req.url ~ "^/widgets/checkout" ||
        req.url ~ "^/widgets/account"
    ) {
        return (pass);
    }

    # --- Session cookie — Shopware sets `session-` on logged-in users
    # and on carts. Any session cookie → bypass cache. -------------------
    if (req.http.Cookie ~ "session-") {
        return (pass);
    }

    # Strip every cookie that's not session-related so Varnish gets a
    # cacheable cache key.
    set req.http.Cookie = ";" + req.http.Cookie;
    set req.http.Cookie = regsuball(req.http.Cookie, "; +", ";");
    set req.http.Cookie = regsuball(req.http.Cookie, ";(sf_redirect|sw-states|sw-currency|sw-language)=", "; \1=");
    set req.http.Cookie = regsuball(req.http.Cookie, ";[^ ][^;]*", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "^[; ]+|[; ]+$", "");
    if (req.http.Cookie == "") {
        unset req.http.Cookie;
    }

    return (hash);
}

sub vcl_hash {
    # Per-host (multi-channel) + per-protocol cache key.
    hash_data(req.http.host);
    hash_data(req.url);
    if (req.http.X-Forwarded-Proto) {
        hash_data(req.http.X-Forwarded-Proto);
    }
    # Shopware sets sw-states cookie per currency/language; vary by it.
    if (req.http.Cookie ~ "sw-states") {
        hash_data(regsub(req.http.Cookie, ".*sw-states=([^;]+).*", "\1"));
    }
}

sub vcl_backend_response {
    # Shopware tells us when a response is uncacheable.
    if (beresp.http.X-Shopware-Allow-Nocache) {
        set beresp.uncacheable = true;
        return (deliver);
    }

    # Default TTL when the backend didn't set Cache-Control — mirrors
    # SHOPWARE_HTTP_DEFAULT_TTL.
    if (beresp.http.Cache-Control !~ "max-age" && !beresp.http.Set-Cookie) {
        set beresp.ttl = 2h;
    }

    # Stale-while-revalidate — serve slightly-stale content during a deploy
    # rather than thundering the backend.
    set beresp.grace = 2m;
    set beresp.keep  = 10m;

    # Strip Set-Cookie on cacheable responses; otherwise Varnish refuses
    # to cache. This is correct because anything with state set Allow-Nocache.
    if (beresp.ttl > 0s && !beresp.http.X-Shopware-Allow-Nocache) {
        unset beresp.http.Set-Cookie;
    }
}

sub vcl_deliver {
    # Expose hit/miss for debugging — `curl -I shop.example.com | grep X-Cache`.
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
        set resp.http.X-Cache-Hits = obj.hits;
    } else {
        set resp.http.X-Cache = "MISS";
    }
    # Don't leak the cache-tag header back to clients — it's only meant for
    # BAN matching, not for browsers / CDNs.
    unset resp.http.X-Cache-Tags;
}

sub vcl_synth {
    if (resp.status == 200 || resp.status == 405) {
        set resp.http.Content-Type = "text/plain; charset=utf-8";
        synthetic(resp.reason);
        return (deliver);
    }
}
