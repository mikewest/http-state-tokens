all:
	kramdown-rfc2629 draft-west-http-state-tokens.md > draft-west-http-state-tokens.xml
	~/.local/bin/xml2rfc draft-west-http-state-tokens.xml
	rm ./draft-west-http-state-tokens.xml
