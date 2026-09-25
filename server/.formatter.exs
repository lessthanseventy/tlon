[
  plugins: [Quokka],
  quokka: [exclude: [:inefficient_functions], files: %{excluded: ["lib/server/web/router.ex"]}],
  line_length: 120,
  import_deps: [:ecto, :ecto_sql, :anubis_mcp],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
