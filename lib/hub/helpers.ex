defmodule Nerves.Hub.Helpers do

  # converts a binary (or list of binaries) to atoms
  def atomify([h|t]), do: [atomify(h) | atomify(t)]
  def atomify(s) when is_binary(s), do: String.to_atom(s)
  def atomify(o), do: o

  def demapify({k, v}) when is_map(v), do: {k, demapify(v)}
  def demapify(e) when is_list(e) or is_map(e), do: Enum.map(e, &(demapify(&1)))
  def demapify(x), do: x

end
