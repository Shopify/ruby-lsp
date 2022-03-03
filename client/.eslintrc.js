/* eslint-env node */

// eslint-disable-next-line no-process-env
const isVsCode = Boolean(process.env.VSCODE_CWD);

const developmentOverrides = isVsCode
  ? {
      "no-console": "warn",
      "@shopify/no-debugger": "warn",
    }
  : {};

module.exports = {
  extends: ["plugin:@shopify/typescript", "plugin:@shopify/prettier"],
  rules: {
    "consistent-return": "off",
    "no-warning-comments": "off",
    ...developmentOverrides,
  },
  settings: {
    "import/resolver": {
      typescript: {
        project: "tsconfig.json",
      },
    },
  },
};
