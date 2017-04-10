BEAMS = $(patsubst src/%.erl, ebin/%.beam, $(wildcard src/*.erl))


all: ebin $(BEAMS)


clean:
	@rm -rf ebin


ebin:
	@mkdir -p ebin


ebin/%.beam: src/%.erl
	@echo "compiling $<"
	@erlc -o ebin $<
