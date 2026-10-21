%{
  configs: [
    %{
      name: "default",
      plugins: [{ExSlop, []}],
      checks: [{ExSlop.Check.Refactor.LengthComparison, files: %{excluded: ["test/"]}}]
    }
  ]
}
