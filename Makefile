PATH := ./node_modules/.bin:${PATH}

.PHONY : init clean-docs clean build dist publish

init:
	npm install

docs:
	docco src/*.coffee

clean-docs:
	rm -rf docs/

clean: clean-docs
	rm -rf lib/

build:
	coffee -o lib/ -c src/

dist: clean init docs build

publish: dist
	npm publish
