#[
pending https://github.com/nim-lang/Nim/pull/10530
note: nimble init installs something like this (maybe without src in this case)
switch("path", "$projectDir/../src")
but it doesn't seem robust in case tests have subdirs, so, changing to ../ seems better
]#
switch("path", "..")
