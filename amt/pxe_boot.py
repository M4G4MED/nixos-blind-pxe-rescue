import sys, time
sys.path.insert(0, './intel_amt_lib')
from ansible_collections.james_crowley.intel_amt.plugins.module_utils.wsman import WsmanClient
from ansible_collections.james_crowley.intel_amt.plugins.module_utils import boot as bootmod
from ansible_collections.james_crowley.intel_amt.plugins.module_utils import client as clientmod

import os
PW = os.environ['AMT_PASSWORD']   # never hardcode; export before running
c = WsmanClient(host='192.0.2.20', port=16992, username='admin', password=PW,
                use_tls=False, allow_insecure_transport=True)
bootmod.discover_and_validate(c, 'pxe')
bootmod.arm_one_time_boot(c, 'pxe', action_token='amt-pxe-%d' % int(time.time()))
print('one-time PXE boot ARMED')
cli = clientmod.AmtClient(c)
try:
    cli.request_power_state(clientmod.PowerAction.RESET)
    print('HARD-RESET-SENT (AMT)')
except Exception as e:
    print('AmtClient power failed:', e, '— raw CIM fallback')
    c.invoke('CIM_ComputerSystem', 'RequestStateChange', {'RequestedState': 10},
             selectors={'CreationClassName': 'CIM_ComputerSystem', 'Name': 'Intel(r) AMT'})
    print('HARD-RESET-SENT (CIM)')
