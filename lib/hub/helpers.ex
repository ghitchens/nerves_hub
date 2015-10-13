defmodule Nerves.Hub.Helpers do

  # converts a binary (or list of binaries) to atoms
  def atomify([h|t]), do: [atomify(h) | atomify(t)]
  def atomify(s) when is_binary(s), do: String.to_atom(s)
  def atomify(o), do: o

end
