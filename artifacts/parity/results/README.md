# Differential corpus results

`corpus.md` lands here on every suite run, written by
`test/unit/test_parity_corpus.gd`. It is machine output and is not committed:
what is committed is the corpus itself (`test/parity/contracts/`) and the runner
that checks it (`test/parity/godot/`).

The directory is committed rather than created on demand so that a checkout has
somewhere obvious to look, and so this note is where somebody looking for the
results finds out what they are.
