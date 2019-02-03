##[
Module that should import everything so that `nim doc --project nimtero/api` runs docs on everything.
]##

# TODO: make sure it does import everything.

import "."/[cimport, git, types, plugin, compat]
