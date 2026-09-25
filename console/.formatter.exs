[
  plugins: [Quokka],
  quokka: [exclude: [:inefficient_functions]],
  line_length: 120,
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
