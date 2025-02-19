import path from "path";
import fs from "fs/promises";
import assert from "assert";

import * as vsctm from "vscode-textmate";
import * as oniguruma from "vscode-oniguruma";

interface InferrableLanguageConfig {
  label: string;
  id?: string;
  delimiters?: string | string[];
  contentName?: string;
  includeName?: string;
}

type InferrableLanguageConfigOrLabel = InferrableLanguageConfig | string;

interface LanguageConfig {
  label: string;
  name: string;
  delimiters: string[];
  contentName: string;
  includeName: string;
}

const EMBEDDED_HEREDOC_LANGUAGES: InferrableLanguageConfigOrLabel[] = [
  // Languages for which we can infer everything from the comment label
  "C",
  "CSS",
  "Lua",
  "Ruby",
  "SQL",

  // Languages requiring at least one override
  {
    id: "cpp",
    label: "C++",
  },
  {
    label: "GraphQL",
    delimiters: ["GRAPHQL", "GQL"],
  },
  {
    label: "HAML",
    contentName: "text.haml",
  },
  {
    label: "HTML",
    contentName: "text.html",
    includeName: "text.html.basic",
  },
  {
    id: "js",
    label: "Javascript",
    delimiters: ["JS", "JAVASCRIPT"],
    contentName: "source.js",
  },
  {
    id: "js.jquery",
    label: "jQuery Javascript",
    delimiters: "JQUERY",
    contentName: "source.js.jquery",
  },
  {
    label: "Shell",
    delimiters: ["SH", "SHELL"],
  },
  {
    label: "Slim",
    contentName: "text.slim",
  },
  {
    label: "XML",
    contentName: "text.xml",
  },
  {
    label: "YAML",
    delimiters: ["YAML", "YML"],
  },
];

// This file runs from inside the out/test directory
const repoRoot = path.join(__dirname, "../../../");
const filename = path.relative(path.join(repoRoot, "out"), __filename);

suite("Grammars", () => {
  suite("ruby", () => {
    const grammarPath = "grammars/ruby.cson.json";
    const rbsGrammarPath = "grammars/rbs.injection.json";

    let rubyGrammar: vsctm.IGrammar | null = null;
    let rbsGrammar: vsctm.IGrammar | null = null;

    suiteSetup(async () => {
      const wasmBin = await fs.readFile(
        path.join(
          repoRoot,
          "./node_modules/vscode-oniguruma/release/onig.wasm",
        ),
      );
      const vscodeOnigurumaLib = oniguruma
        .loadWASM(Buffer.from(wasmBin).buffer)
        .then(() => {
          return {
            createOnigScanner(patterns: string[]) {
              return new oniguruma.OnigScanner(patterns);
            },
            createOnigString(str: string) {
              return new oniguruma.OnigString(str);
            },
          };
        });
      const registry = new vsctm.Registry({
        onigLib: vscodeOnigurumaLib,
        loadGrammar: async (scopeName) => {
          if (scopeName === "source.ruby") {
            const data = await fs.readFile(
              path.join(repoRoot, grammarPath),
              "utf8",
            );
            return vsctm.parseRawGrammar(data, grammarPath);
          } else if (scopeName === "rbs-comment.injection") {
            const data = await fs.readFile(
              path.join(repoRoot, rbsGrammarPath),
              "utf8",
            );
            return vsctm.parseRawGrammar(data, rbsGrammarPath);
          }

          // We expect to run unto unsupported grammars for the embedded languages.
          return null;
        },
      });

      rubyGrammar = await registry.loadGrammar("source.ruby");
      rbsGrammar = await registry.loadGrammar("rbs-comment.injection");

      if (!rubyGrammar) {
        throw new Error("Failed to load Ruby grammar");
      }

      if (!rbsGrammar) {
        throw new Error("Failed to load RBS grammar");
      }
    });

    suite("embedded HEREDOC languages", () => {
      const languageConfigs: LanguageConfig[] = EMBEDDED_HEREDOC_LANGUAGES.map(
        (languageConfigOrLabel: InferrableLanguageConfigOrLabel) => {
          const languageConfig =
            typeof languageConfigOrLabel === "string"
              ? { label: languageConfigOrLabel }
              : languageConfigOrLabel;

          const label: string = languageConfig.label;

          // Infer omitted values
          const id: string = languageConfig.id ?? label.toLowerCase();
          const name = `meta.embedded.block.${id}`;
          const contentName: string =
            languageConfig.contentName ?? `source.${id}`;
          const includeName: string = languageConfig.includeName ?? contentName;

          // Infer, normalize, and validate delimiters
          let delimiters: string | string[] =
            languageConfig.delimiters ?? id.toUpperCase();
          if (Array.isArray(delimiters)) {
            if (delimiters.length === 0) {
              throw new Error(
                `Must provide at least one delimiter for ${label}`,
              );
            }
          } else {
            delimiters = [delimiters];
          }
          return { label, name, delimiters, contentName, includeName };
        },
      );

      languageConfigs.forEach((languageConfig) => {
        test(`Config for ${languageConfig.label} is included`, async () => {
          const grammar = await readRelativeJSONFile(grammarPath);
          const actual = grammar.patterns.find(
            (pattern: { name: string }) => pattern.name === languageConfig.name,
          );

          assert(
            actual,
            `No grammar pattern found for ${languageConfig.name} in ${grammarPath}`,
          );

          const expected = expectedEmbeddedLanguageConfig(languageConfig);

          assert.deepStrictEqual(
            actual,
            expected,
            `Grammar pattern for embedded ${languageConfig.label} in HEREDOC does not match expected config.\n` +
              `Update the entry for ${languageConfig.name} in ${grammarPath}, or if it is correct, ` +
              `update EMBEDDED_HEREDOC_LANGUAGES in ${filename}`,
          );
        });

        languageConfig.delimiters.forEach((delimiter) => {
          test(`HEREDOC using ${delimiter} is tokenized correctly`, () => {
            const expectedTokens = [
              [
                `<<~${delimiter}`,
                [
                  "source.ruby",
                  languageConfig.name,
                  "string.unquoted.heredoc.ruby",
                  "punctuation.definition.string.begin.ruby",
                ],
              ],
              [
                delimiter,
                [
                  "source.ruby",
                  languageConfig.name,
                  "string.unquoted.heredoc.ruby",
                  "punctuation.definition.string.end.ruby",
                ],
              ],
            ];
            const ruby = expectedTokens.map((token) => token[0]).join("\n");
            const actualTokens = tokenizeRuby(ruby);

            assert.deepStrictEqual(
              actualTokens,
              expectedTokens,
              `Tokens did not match expected for HEREDOC using ${delimiter}.`,
            );
          });
        });
      });

      test("No unknown languages are included", async () => {
        const grammar = await readRelativeJSONFile(grammarPath);
        const expected = languageConfigs
          .map((languageConfig) => languageConfig.name)
          .sort();
        const actual = grammar.patterns
          .map((pattern: { name: string }) => pattern.name)
          .filter((name?: string) => name?.startsWith("meta.embedded.block."))
          .sort();

        const filename = path.relative(path.join(repoRoot, "out"), __filename);

        const unexpected = actual.filter(
          (name: string) => !expected.includes(name),
        );

        assert.deepStrictEqual(
          unexpected,
          [],
          `Unexpected languages included.\n` +
            `If you're trying to add a new language, please update EMBEDDED_HEREDOC_LANGUAGES in ${filename}`,
        );
      });

      test("EMBEDDED_HEREDOC_LANGUAGES is sorted", () => {
        const isLabel = (
          languageConfigOrLabel: InferrableLanguageConfigOrLabel,
        ): languageConfigOrLabel is string => {
          return typeof languageConfigOrLabel === "string";
        };
        const sortedLanguages = EMBEDDED_HEREDOC_LANGUAGES.toSorted(
          (language1, language2) => {
            const label1 = isLabel(language1) ? language1 : language1.label;
            const label2 = isLabel(language2) ? language2 : language2.label;
            return label1.localeCompare(label2);
          },
        );

        const [labelsOnly, objects] = [
          sortedLanguages.filter((object) => isLabel(object)),
          sortedLanguages.filter((object) => !isLabel(object)),
        ];

        assert.deepStrictEqual(
          EMBEDDED_HEREDOC_LANGUAGES,
          [...labelsOnly, ...objects],
          "EMBEDDED_HEREDOC_LANGUAGES label entries are not sorted",
        );
      });
    });

    suite("Backtick String Literals", () => {
      test("Standard backtick string", () => {
        const ruby = "`ruby`";
        const expectedTokens = [
          [
            "`",
            [
              "source.ruby",
              "string.interpolated.ruby",
              "punctuation.definition.string.begin.ruby",
            ],
          ],
          ["ruby", ["source.ruby", "string.interpolated.ruby"]],
          [
            "`",
            [
              "source.ruby",
              "string.interpolated.ruby",
              "punctuation.definition.string.end.ruby",
            ],
          ],
        ];
        const actualTokens = tokenizeRuby(ruby);
        assert.deepStrictEqual(actualTokens, expectedTokens);
      });

      test("Kernel backtick method", () => {
        const ruby = 'Kernel.`"ls"';
        const expectedTokens = [
          ["Kernel", ["source.ruby", "variable.other.constant.ruby"]],
          [".", ["source.ruby", "punctuation.separator.method.ruby"]],
          ["`", ["source.ruby"]],
          [
            '"',
            [
              "source.ruby",
              "string.quoted.double.interpolated.ruby",
              "punctuation.definition.string.begin.ruby",
            ],
          ],
          ["ls", ["source.ruby", "string.quoted.double.interpolated.ruby"]],
          [
            '"',
            [
              "source.ruby",
              "string.quoted.double.interpolated.ruby",
              "punctuation.definition.string.end.ruby",
            ],
          ],
        ];
        const actualTokens = tokenizeRuby(ruby);
        assert.deepStrictEqual(actualTokens, expectedTokens);
      });
    });

    suite("rbs", () => {
      test("inline method signature", () => {
        const ruby = "#: (String) -> (String | nil)";
        const expectedTokens = [
          [
            "#:",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "(",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [
            "String",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "variable.other.constant.rbs",
            ],
          ],
          [
            ")",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "->",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "(",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [
            "String",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "variable.other.constant.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "|",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "nil",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "support.type.builtin.rbs",
            ],
          ],
          [
            ")",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
        ];
        const actualTokens = tokenizeRBS(ruby);
        assert.deepStrictEqual(actualTokens, expectedTokens);
      });

      test("inline method signature with block", () => {
        const ruby = "#: (String) { (String) -> boolish } -> void";
        const expectedTokens = [
          [
            "#:",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "(",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [
            "String",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "variable.other.constant.rbs",
            ],
          ],
          [
            ")",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "{",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "(",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [
            "String",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "variable.other.constant.rbs",
            ],
          ],
          [
            ")",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "->",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "boolish",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "support.type.builtin.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "}",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "->",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "void",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "support.type.builtin.rbs",
            ],
          ],
        ];
        const actualTokens = tokenizeRBS(ruby);
        assert.deepStrictEqual(actualTokens, expectedTokens);
      });

      test("inline method signature with &", () => {
        const ruby = "#: [X] (X & Object) -> Class[X]";
        const expectedTokens = [
          [
            "#:",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "[",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "variable.other.constant.rbs",
            ],
          ],
          [
            "X",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "variable.other.constant.rbs",
            ],
          ],
          [
            "]",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "variable.other.constant.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "(",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [
            "X",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "variable.other.constant.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "&",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "Object",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "variable.other.constant.rbs",
            ],
          ],
          [
            ")",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "->",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "Class",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "variable.other.constant.rbs",
            ],
          ],
          [
            "[",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "variable.other.constant.rbs",
            ],
          ],
          [
            "X",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "variable.other.constant.rbs",
            ],
          ],
          [
            "]",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "variable.other.constant.rbs",
            ],
          ],
        ];
        const actualTokens = tokenizeRBS(ruby);
        assert.deepStrictEqual(actualTokens, expectedTokens);
      });

      test("inline method signature * and **", () => {
        const ruby = "#: (*Foo, **Bar) -> void";
        const expectedTokens = [
          [
            "#:",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "(",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [
            "*",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [
            "Foo",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "variable.other.constant.rbs",
            ],
          ],
          [
            ",",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "*",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [
            "*",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [
            "Bar",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "variable.other.constant.rbs",
            ],
          ],
          [
            ")",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "->",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "void",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "support.type.builtin.rbs",
            ],
          ],
        ];

        const actualTokens = tokenizeRBS(ruby);
        assert.deepStrictEqual(actualTokens, expectedTokens);
      });

      test("inline method signature with keyword", () => {
        const ruby = "#: return: String";
        const expectedTokens = [
          [
            "#:",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "comment.line.number-sign.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "return:",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "constant.other.symbol.hashkey.parameter.function.rbs",
            ],
          ],
          [" ", ["rbs-comment.injection", "meta.type.signature.rbs"]],
          [
            "String",
            [
              "rbs-comment.injection",
              "meta.type.signature.rbs",
              "variable.other.constant.rbs",
            ],
          ],
        ];
        const actualTokens = tokenizeRBS(ruby);
        assert.deepStrictEqual(actualTokens, expectedTokens);
      });
    });

    suite("Local variables", () => {
      test("rescue is not confused", () => {
        const ruby = "rescue => e";
        const expectedTokens = [
          ["rescue", ["source.ruby", "keyword.control.ruby"]],
          [" ", ["source.ruby"]],
          ["=>", ["source.ruby", "punctuation.separator.key-value"]],
          [" e", ["source.ruby"]],
        ];
        const actualTokens = tokenizeRuby(ruby);
        assert.deepStrictEqual(actualTokens, expectedTokens);
      });

      test("or assignment", () => {
        const ruby = "local ||= 1";
        const expectedTokens = [
          ["local", ["source.ruby", "variable.ruby"]],
          [" ", ["source.ruby"]],
          [
            "||=",
            ["source.ruby", "keyword.operator.assignment.augmented.ruby"],
          ],
          [" ", ["source.ruby"]],
          ["1", ["source.ruby", "constant.numeric.ruby"]],
        ];
        const actualTokens = tokenizeRuby(ruby);
        assert.deepStrictEqual(actualTokens, expectedTokens);
      });

      test("and assignment in a condition", () => {
        const ruby = "if local &&= 1";
        const expectedTokens = [
          ["if", ["source.ruby", "keyword.control.ruby"]],
          [" ", ["source.ruby"]],
          ["local", ["source.ruby", "variable.ruby"]],
          [" ", ["source.ruby"]],
          [
            "&&=",
            ["source.ruby", "keyword.operator.assignment.augmented.ruby"],
          ],
          [" ", ["source.ruby"]],
          ["1", ["source.ruby", "constant.numeric.ruby"]],
        ];
        const actualTokens = tokenizeRuby(ruby);
        assert.deepStrictEqual(actualTokens, expectedTokens);
      });

      test("assignment in a condition", () => {
        const ruby = "if (local = 1)";
        const expectedTokens = [
          ["if", ["source.ruby", "keyword.control.ruby"]],
          [" (", ["source.ruby"]],
          ["local", ["source.ruby", "variable.ruby"]],
          [" = ", ["source.ruby"]],
          ["1", ["source.ruby", "constant.numeric.ruby"]],
          [")", ["source.ruby", "punctuation.section.function.ruby"]],
        ];
        const actualTokens = tokenizeRuby(ruby);
        assert.deepStrictEqual(actualTokens, expectedTokens);
      });

      test("operation assignment in a condition", () => {
        const ruby = "if (local += 1)";
        const expectedTokens = [
          ["if", ["source.ruby", "keyword.control.ruby"]],
          [" (", ["source.ruby"]],
          ["local", ["source.ruby", "variable.ruby"]],
          [" ", ["source.ruby"]],
          ["+=", ["source.ruby", "keyword.operator.assignment.augmented.ruby"]],
          [" ", ["source.ruby"]],
          ["1", ["source.ruby", "constant.numeric.ruby"]],
          [")", ["source.ruby", "punctuation.section.function.ruby"]],
        ];
        const actualTokens = tokenizeRuby(ruby);
        assert.deepStrictEqual(actualTokens, expectedTokens);
      });

      test("assignment to a string with no spaces", () => {
        const ruby = "local='string'";
        const expectedTokens = [
          ["local", ["source.ruby", "variable.ruby"]],
          ["=", ["source.ruby", "keyword.operator.assignment.ruby"]],
          [
            "'",
            [
              "source.ruby",
              "string.quoted.single.ruby",
              "punctuation.definition.string.begin.ruby",
            ],
          ],
          ["string", ["source.ruby", "string.quoted.single.ruby"]],
          [
            "'",
            [
              "source.ruby",
              "string.quoted.single.ruby",
              "punctuation.definition.string.end.ruby",
            ],
          ],
        ];
        const actualTokens = tokenizeRuby(ruby);
        assert.deepStrictEqual(actualTokens, expectedTokens);
      });
    });

    function tokenizeRBS(rbs: string): [string, string[]][] {
      if (!rbsGrammar) {
        throw new Error("RBS grammar not loaded");
      }

      const lines = rbs.split("\n");
      let ruleStack = vsctm.INITIAL;

      // Typescript's flow sensitive typing doesn't seem to extend into the next function, so we re-assign the value
      const grammar = rbsGrammar;

      const tokens = lines.flatMap((line) => {
        const lineTokens = grammar.tokenizeLine(line, ruleStack);
        ruleStack = lineTokens.ruleStack;

        return lineTokens.tokens.map((token) => {
          const tokenString = line.substring(token.startIndex, token.endIndex);
          const pair: [string, string[]] = [tokenString, token.scopes];
          return pair;
        });
      });

      return tokens;
    }

    function tokenizeRuby(ruby: string): [string, string[]][] {
      if (!rubyGrammar) {
        throw new Error("Ruby grammar not loaded");
      }

      const lines = ruby.split("\n");
      let ruleStack = vsctm.INITIAL;

      // Typescript's flow sensitive typing doesn't seem to extend into the next function, so we re-assign the value
      const grammar = rubyGrammar;

      const tokens = lines.flatMap((line) => {
        const lineTokens = grammar.tokenizeLine(line, ruleStack);
        ruleStack = lineTokens.ruleStack;

        return lineTokens.tokens.map((token) => {
          const tokenString = line.substring(token.startIndex, token.endIndex);
          const pair: [string, string[]] = [tokenString, token.scopes];
          return pair;
        });
      });

      return tokens;
    }

    function expectedEmbeddedLanguageConfig(languageConfig: LanguageConfig) {
      const { label, name, delimiters, contentName, includeName } =
        languageConfig;
      const delimiter =
        delimiters.length > 1 ? `(?:${delimiters.join("|")})` : delimiters;

      return {
        begin: `(?=(?><<[-~](["'\`]?)((?:[_\\w]+_|)${delimiter})\\b\\1))`,
        comment: `Heredoc with embedded ${label}`,
        end: "(?!\\G)",
        name,
        patterns: [
          {
            begin: `(?><<[-~](["'\`]?)((?:[_\\w]+_|)${delimiter})\\b\\1)`,
            beginCaptures: {
              // eslint-disable-next-line @typescript-eslint/naming-convention
              "0": { name: "punctuation.definition.string.begin.ruby" },
            },
            contentName,
            end: "^\\s*\\2$\\n?",
            endCaptures: {
              // eslint-disable-next-line @typescript-eslint/naming-convention
              "0": { name: "punctuation.definition.string.end.ruby" },
            },
            name: "string.unquoted.heredoc.ruby",
            patterns: [
              { include: "#heredoc" },
              { include: "#interpolated_ruby" },
              { include: includeName },
              { include: "#escaped_char" },
            ],
          },
        ],
      };
    }
  });
});

async function readRelativeJSONFile(relativePath: string) {
  return JSON.parse(
    await fs.readFile(path.join(repoRoot, relativePath), "utf8"),
  );
}
