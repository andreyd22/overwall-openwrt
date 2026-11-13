#!/usr/bin/ucode
'use strict';
import * as store from 'overwall.store';
import * as network from 'overwall.network';

let state = store.state();
if (state.protected && !store.read('tunnel', true) && !store.read('portal', true) && match(state.device || '', /^[a-zA-Z0-9_.:-]{1,32}$/)) network.guard('closed', state.device);
