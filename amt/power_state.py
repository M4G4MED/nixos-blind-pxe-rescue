#!/usr/bin/env python3
import sys
sys.path.insert(0, './intel_amt_lib')
from ansible_collections.james_crowley.intel_amt.plugins.module_utils.wsman import WsmanClient
from ansible_collections.james_crowley.intel_amt.plugins.module_utils import client as clientmod

import os
PW = os.environ['AMT_PASSWORD']   # never hardcode; export before running
with WsmanClient(host='192.0.2.20', port=16992, username='admin', password=PW,
                 use_tls=False, allow_insecure_transport=True) as c:
    cli = clientmod.AmtClient(c)
    print('AMT power:', cli.get_power_state())
