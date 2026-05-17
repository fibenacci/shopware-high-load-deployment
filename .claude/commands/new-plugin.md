---
description: Scaffold a new Shopware static plugin under custom/static-plugins/.
argument-hint: "<PluginName> (PascalCase)"
---

# /new-plugin

Scaffold a new Shopware static plugin. Delegate the implementation to
the `shopware-plugin` agent — this command's job is just to invoke the
agent with the right framing.

## Process

1. **Validate the name** — PascalCase, project prefix (e.g. `MyShop`)
   to avoid clashes with store plugins. Reject snake_case, kebab-case.
2. **Confirm scope** with one question:
   - "What's the plugin's purpose in one sentence?"
3. **Hand to `shopware-plugin` agent** with this brief:

   ```
   Scaffold a new static plugin called <PluginName>.
   Purpose: <one-sentence purpose>.
   Path: custom/static-plugins/<PluginName>/

   Generate:
   - composer.json with extra.shopware-plugin-class
   - src/<PluginName>.php (extends Plugin, lifecycle stubs commented
     "see /docs/shopware/plugin-lifecycle.html")
   - src/Resources/config/services.xml (empty <services> block)
   - src/Resources/snippet/{de_DE,en_GB}/messages.<locale>.json (empty {})
   - tests/Unit/.gitkeep
   - tests/Integration/.gitkeep
   - phpunit.xml.dist

   Do NOT generate placeholder Service / Subscriber / Controller classes
   — wait for the user to ask for those.
   ```

4. **After the agent finishes**: run `shopware-cli extension validate
   custom/static-plugins/<PluginName>` and report the result.
5. **Suggest next steps** — usually one of:
   - "Add a Subscriber" → re-invoke `shopware-plugin`
   - "Add the admin UI" → invoke `shopware-frontend`
   - "Write the first test" → invoke `shopware-test-writer`

Argument: `$ARGUMENTS` — plugin name (PascalCase).
