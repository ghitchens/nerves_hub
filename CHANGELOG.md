# 2016-03-17 0.10.1

- removed VERSION file in favor of version
- removed internal implementation of UUID in favor of nerves_lib
- fixed bug with UUID generation happening at compile rather than runtime

# 2016-02-24 0.10.0-pre

- Changed response from Hub.watch to include current node
- Added tests better tests for "no changes" case
- IO.write inspect(Hub.fetch ["q", "r", "s"])
- Renamed project to Nerves.Hub during merge to Nerves
- cleanup of HISTORY.md (this file)
- added better tests
- refactored for nerves

# 2015-09-15 0.9.0

- Broke apart from the private "Echo Project" git@github.com:ghitchens/echo.git
- Changed license from proprietary to MIT
- Chris dutton translated hub.erl to hub.ex
- Updated tests to reflect only hub use
- First publish to cellulose project git@github.com:cellulose/hub.git
