# Re-evaluates every notebook code cell and rewrites the saved output blocks.
#
#     mix run scripts/regen_notebook_outputs.exs
#
# Keep this in sync with test/notebooks_test.exs, which verifies the same
# outputs without writing.

Code.require_file("notebook_outputs.exs", __DIR__)

for path <- ExBooking.NotebookOutputs.notebook_paths() do
  text = File.read!(path)
  updated = ExBooking.NotebookOutputs.rewrite(text, path)

  if updated == text do
    IO.puts("unchanged  #{Path.relative_to_cwd(path)}")
  else
    File.write!(path, updated)
    IO.puts("rewrote    #{Path.relative_to_cwd(path)}")
  end
end
