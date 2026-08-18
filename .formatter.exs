[
  inputs: [
    "{mix,.check,.doctor,.formatter}.exs",
    "{bench,config,lib,scripts,test}/**/*.{ex,exs}"
  ],
  plugins: [DoctestFormatter]
]
