# Makefile for Sphinx documentation
#

# You can set these variables from the command line.
SPHINXOPTS    = -W --keep-going -n
SPHINXBUILD   = sphinx-build
PAPER         =
BUILDDIR      = _build

# User-friendly check for sphinx-build
ifeq ($(shell which $(SPHINXBUILD) >/dev/null 2>&1; echo $$?), 1)
$(error The '$(SPHINXBUILD)' command was not found. Try 'running pip install -r requirements.txt' to get the necessary Python dependencies.)
endif

# Internal variables.
PAPEROPT_a4     = -D latex_paper_size=a4
PAPEROPT_letter = -D latex_paper_size=letter
ALLSPHINXOPTS   = -d $(BUILDDIR)/doctrees $(PAPEROPT_$(PAPER)) $(SPHINXOPTS) .
# the i18n builder cannot share the environment and doctrees with the others
I18NSPHINXOPTS  = $(PAPEROPT_$(PAPER)) $(SPHINXOPTS) .

.PHONY: help clean html epub changes linkcheck refresh-bib

help:
	@echo "Please use \`make <target>' where <target> is one of"
	@echo "  html         to make standalone HTML files"
	@echo "  epub         to make an epub"
	@echo "  linkcheck    to check all external links for integrity"
	@echo "  refresh-bib  to update LSST bibliographies in lsstbib/"

clean:
	rm -rf $(BUILDDIR)/*

html:
	$(SPHINXBUILD) -b html $(ALLSPHINXOPTS) $(BUILDDIR)/html
	@echo
	@echo "Build finished. The HTML pages are in $(BUILDDIR)/html."

epub:
	$(SPHINXBUILD) -b epub $(ALLSPHINXOPTS) $(BUILDDIR)/epub
	@echo
	@echo "Build finished. The epub file is in $(BUILDDIR)/epub."

changes:
	$(SPHINXBUILD) -b changes $(ALLSPHINXOPTS) $(BUILDDIR)/changes
	@echo
	@echo "The overview file is in $(BUILDDIR)/changes."

linkcheck:
	$(SPHINXBUILD) -b linkcheck $(ALLSPHINXOPTS) $(BUILDDIR)/linkcheck
	@echo
	@echo "Link check complete; look for any errors in the above output " \
	      "or in $(BUILDDIR)/linkcheck/output.txt."

refresh-bib:
	refresh-lsst-bib -d lsstbib
	@echo
	@echo "Commit the new bibliographies: git add lsstbib && git commit -m \"Update bibliographies.\""
