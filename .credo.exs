%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      strict: true,
      color: true,
      checks: [
        {Credo.Check.Readability.MaxLineLength, max_length: 120},
        # Generated Phoenix files use inline module references intentionally
        {Credo.Check.Design.AliasUsage, false}
      ]
    }
  ]
}
