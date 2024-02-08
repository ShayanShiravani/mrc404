include .env

.PHONY: all test

test:
	forge test --gas-report -vvvv