#!/usr/bin/ucode
'use strict';
import * as fs from 'fs';
import { command } from 'overwall.client';

try {
	let input = ARGV[1] ? json(fs.readfile(ARGV[1])) : {};
	printf('%J\n', command(ARGV[0] || 'status', input));
} catch (e) {
	// Do not serialize exception stacks: these can contain credentials/input.
	printf('%J\n', { error: 'Operation failed. Check the input, network and account access.' });
	exit(1);
}
