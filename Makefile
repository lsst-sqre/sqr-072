.PHONY:
init:
	pip install tox pre-commit
	pre-commit install

.PHONY:
html:
	tox run -e html

.PHONY:
lint:
	tox run -e lint,linkcheck

.PHONY:
add-author:
	tox run -e add-author

.PHONY:
sync-authors:
	tox run -e sync-authors

.PHONY:
clean:
	rm -rf _build
	rm -rf .technote
	rm -rf .tox
