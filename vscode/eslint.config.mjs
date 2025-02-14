import shopifyPlugin from "@shopify/eslint-plugin";

const config = [
  ...shopifyPlugin.configs.core,
  ...shopifyPlugin.configs.typescript,
  ...shopifyPlugin.configs.prettier,
  {
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },

    "rules": {
      "@typescript-eslint/no-floating-promises": "error",
      "consistent-return": "off",
      "no-warning-comments": "off",
      "no-console": "warn",
      "@shopify/no-debugger": "warn",
      "no-template-curly-in-string": "warn",
      "eqeqeq": "error",
      "no-invalid-this": "error",
      "no-lonely-if": "error",
      "max-len": [
        "error",
        {
          "code": 120
        }
      ]
    }
  },
  {
    ignores: [
      ".vscode-test/*",
    ],
  }
]

export default config;
