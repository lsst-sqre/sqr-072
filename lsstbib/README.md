# lsstbib

This directory contains local copies of LSST's common LaTeX bibliographies from [lsst-texmf](https://github.com/lsst/lsst-texmf/tree/main/texmf/bibtex/bib).
The recommended way to update these files is with (from the root technote directory):

```
make refresh-bib
git add lsstbib
git commit -m "Update lsst bibliographies"
```

Add new bibliography items specifically for this technote to the `local.bib` file in the root directory of this technote.
Later, you should add these bibliography items to `lsst-texmf` and remove them from `local.bib` so that other documents can use the reference.
See the [lsst-texmf docs for instructions](https://lsst-texmf.lsst.io/developer.html#updating-bibliographies).
