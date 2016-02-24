Hub
===

Implements a heirarchial key-value store with publish/watch semanitcs
at each node of the heirarchy. Part of the [nerves](http://nerves-project.org) framework.

## Examples

Basic Usage:

```elixir
# Start Hub
iex> Nerves.Hub.start
{:ok, #PID<0.127.0>}

# Put [status: :online] at path [:some, :point]
iex> Nerves.Hub.put [:some,:point], [status: :online]
{:changes, {"05142ef7fe86a86D2471CA6869E19648", 1},
[some: [point: [status: :online]]]}

# Fetch all values at path [:some, :point]
iex> Nerves.Hub.fetch [:some, :point]
{{"05142ef7fe86a86D2471CA6869E19648", 1}, [status: :online]}

# Get particular value :status at [:some, :point]
iex> Nerves.Hub.get [:some, :point], :status
:online
```
