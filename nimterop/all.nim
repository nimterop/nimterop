##[
Module that should import everything so that `nim doc --project nimtero/all` runs docs on everything.
]##

# TODO: make sure it does import everything.

import "."/[cimport, build, types, plugin]
