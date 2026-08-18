defmodule ExBooking.NotebookOutputs do
  @moduledoc false

  # Shared engine for keeping notebooks/*.livemd honest.
  #
  # A notebook is tokenized into markdown lines, ```elixir code cells, and
  # saved-output blocks (`<!-- livebook:{"output":true} -->`). Code cells are
  # evaluated in order with a threaded binding — exactly Livebook's semantics
  # for alias-free notebooks — and each saved output must equal the canonical
  # rendering of its cell's result.
  #
  # Used by `scripts/regen_notebook_outputs.exs` (rewrite mode) and
  # `test/notebooks_test.exs` (verify mode).

  @output_marker ~s(<!-- livebook:{"output":true} -->)
  @inspect_opts [pretty: true, width: 98, custom_options: [sort_maps: true]]

  @doc "All notebook paths, sorted for determinism."
  @spec notebook_paths() :: [Path.t()]
  def notebook_paths do
    __DIR__
    |> Path.join("../notebooks/*.livemd")
    |> Path.expand()
    |> Path.wildcard()
    |> Enum.sort()
  end

  @doc "The Mix.install pin a setup cell must contain for `version`."
  @spec expected_pin(String.t()) :: String.t()
  def expected_pin(version) do
    [major, minor | _] = String.split(version, ".")
    ~s({:ex_booking, "~> #{major}.#{minor}"})
  end

  @doc "Tokenizes livemd text; `render/1` is its exact inverse."
  @spec tokenize(String.t()) :: [
          {:md, String.t()} | {:code, [String.t()]} | {:output, [String.t()]}
        ]
  def tokenize(text) do
    text
    |> String.split("\n")
    |> do_tokenize([])
  end

  defp do_tokenize([], acc), do: Enum.reverse(acc)

  defp do_tokenize(["```elixir" | rest], acc) do
    {block, rest} = take_until_fence(rest, [])
    do_tokenize(rest, [{:code, block} | acc])
  end

  defp do_tokenize([@output_marker, "", "```" | rest], acc) do
    {block, rest} = take_until_fence(rest, [])
    do_tokenize(rest, [{:output, block} | acc])
  end

  defp do_tokenize([line | rest], acc), do: do_tokenize(rest, [{:md, line} | acc])

  defp take_until_fence(["```" | rest], acc), do: {Enum.reverse(acc), rest}
  defp take_until_fence([line | rest], acc), do: take_until_fence(rest, [line | acc])

  @doc "Renders tokens back to livemd text."
  @spec render([tuple()]) :: String.t()
  def render(tokens) do
    Enum.map_join(tokens, "\n", fn
      {:md, line} -> line
      {:code, block} -> Enum.join(["```elixir" | block] ++ ["```"], "\n")
      {:output, block} -> Enum.join([@output_marker, "", "```" | block] ++ ["```"], "\n")
    end)
  end

  @doc "Source of the setup cell (the first code cell)."
  @spec setup_source(String.t()) :: String.t()
  def setup_source(text) do
    text
    |> tokenize()
    |> Enum.find_value(fn
      {:code, block} -> Enum.join(block, "\n")
      _ -> nil
    end)
  end

  @doc """
  Evaluates every non-setup code cell in order and pairs results with any
  saved output that follows the cell. Returns `{tokens, pairs}` where each
  pair is `{output_token_index, cell_number, rendered_result, saved_lines}`.
  Raises with cell context if a cell fails to evaluate.
  """
  @spec evaluate(String.t(), Path.t()) ::
          {[tuple()], [{non_neg_integer(), pos_integer(), String.t(), [String.t()]}]}
  def evaluate(text, path) do
    tokens = tokenize(text)

    {pairs, _binding, _cell, _result} =
      tokens
      |> Enum.with_index()
      |> Enum.reduce({[], [], 0, :__no_result__}, fn {token, index},
                                                     {pairs, binding, cell, last} ->
        case token do
          {:code, _block} when cell == 0 ->
            # Setup cell: Mix.install cannot run here; skip evaluation.
            {pairs, binding, 1, :__no_result__}

          {:code, block} ->
            {result, binding} = eval_cell(block, binding, path, cell)
            {pairs, binding, cell + 1, result}

          {:output, saved} when last != :__no_result__ ->
            rendered = inspect(last, @inspect_opts)
            {[{index, cell, rendered, saved} | pairs], binding, cell, :__no_result__}

          {:output, _} ->
            raise "#{path}: output block at token #{index} has no preceding evaluated cell"

          {:md, _} ->
            {pairs, binding, cell, last}
        end
      end)

    {tokens, Enum.reverse(pairs)}
  end

  defp eval_cell(block, binding, path, cell) do
    code = Enum.join(block, "\n")

    try do
      {result, binding} = Code.eval_string(code, binding, file: "#{path}:cell-#{cell}")
      {result, binding}
    rescue
      error ->
        reraise(
          "#{Path.basename(path)} cell #{cell} failed: #{Exception.message(error)}\n\n#{code}",
          __STACKTRACE__
        )
    end
  end

  @doc "Rewrites saved outputs in place from evaluation. Returns updated text."
  @spec rewrite(String.t(), Path.t()) :: String.t()
  def rewrite(text, path) do
    {tokens, pairs} = evaluate(text, path)

    replacements =
      Map.new(pairs, fn {index, _cell, rendered, _saved} ->
        {index, {:output, String.split(rendered, "\n")}}
      end)

    tokens
    |> Enum.with_index()
    |> Enum.map(fn {token, index} -> Map.get(replacements, index, token) end)
    |> render()
  end

  @doc "Returns `[{cell, expected, saved}]` for every stale saved output."
  @spec mismatches(String.t(), Path.t()) :: [{pos_integer(), String.t(), String.t()}]
  def mismatches(text, path) do
    {_tokens, pairs} = evaluate(text, path)

    for {_index, cell, rendered, saved} <- pairs,
        saved_text = Enum.join(saved, "\n"),
        saved_text != rendered do
      {cell, rendered, saved_text}
    end
  end
end
