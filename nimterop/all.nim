##[
Module that should import everything so that `nim doc --project nimtero/all` runs docs on everything.
]##

# TODO: make sure it does import everything.

import "."/[docs, cimport, build, types, plugin]
