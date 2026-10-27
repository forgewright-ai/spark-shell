#!/usr/bin/env python3
"""Native scope preservation, live ownership and guarded dhcpcd recovery."""
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
import network_dhcpcd as native


class Config(unittest.TestCase):
    def test_edit_preserves_other_interfaces_comments_and_ipv6(self):
        text = ('# native defaults\noption domain_name_servers\n'
                'interface eth0\n# keep this\nmetric 200\n'
                'static ip_address=192.0.2.2/24\nstatic routers=192.0.2.1\n'
                'static ip6_address=2001:db8::2/64\n'
                'interface wlan0\nmetric 500\n')
        prefix, old, suffix, settings = native.section(text, 'eth0')
        self.assertEqual(settings['ipv4.gateway'], '192.0.2.1')
        new = native.render(old, 'eth0', {**settings, **native.changes('dns', ['192.0.2.53'])})
        self.assertIn('# keep this\nmetric 200\n', new)
        self.assertIn('static ip6_address=2001:db8::2/64\n', new)
        self.assertEqual(prefix + old + suffix, text)
        self.assertTrue(suffix.startswith('interface wlan0\n'))
        auto = native.render(new, 'eth0', native.DEFAULT)
        self.assertNotIn('static ip_address=', auto)
        self.assertIn('static ip6_address=', auto)

    def test_ambiguous_or_special_configuration_is_never_rewritten(self):
        examples = ['profile home\n', 'ssid example\n', 'interface eth*\n',
                    'interface eth0\ninterface eth0\n',
                    'static ip_address=192.0.2.2/24\n',
                    'nohook resolv.conf\n', 'noipv4\n', 'fallback home\n',
                    'interface eth0\nstatic routers=192.0.2.1\n',
                    'interface eth0\nstatic routers=\n',
                    'interface eth0\nstatic domain_name_servers=\n',
                    'interface eth0\nstatic ip_address=192.0.2.2/24\n'
                    'static ip_address=192.0.2.3/24\n']
        for text in examples:
            with self.subTest(text=text), self.assertRaises(native.Refused):
                native.section(text, 'eth0')

    def test_new_section_and_exact_native_round_trip(self):
        text = 'option domain_name_servers\n'
        prefix, old, suffix, settings = native.section(text, 'eth0')
        self.assertEqual(settings, native.DEFAULT)
        self.assertEqual(old, '')
        new = native.render(old, 'eth0', {**settings, **native.changes('address', ['192.0.2.8/24', 'none'])})
        p2, s2, tail, _ = native.section(prefix + new + suffix, 'eth0')
        self.assertEqual(s2, new)
        self.assertEqual(p2 + old + tail, text)

    def test_cached_leases_and_other_interfaces_do_not_prove_ownership(self):
        def query(command):
            return 123, {'--version': '10.3.2', '--getconfigfile': str(native.CONFIG),
                         '--getinterfaces': [{'interface': 'wlan0'}]}[command]
        with patch.object(native, 'query', query), self.assertRaisesRegex(native.Refused, 'does not own'):
            native.owner('eth0')
        with patch.object(native, 'query', query), self.assertRaisesRegex(native.Refused, 'owner or config changed'):
            native.owner('wlan0', 456)

    def test_reconfigure_notice_cannot_confirm_a_new_lease(self):
        row = dict(interface='eth0', if_up='true', reason='RECONFIGURE',
                   new_ip_address='192.0.2.20',
                   new_dhcp_server_identifier='192.0.2.1')
        self.assertFalse(native.live_matches([row], native.DEFAULT))
        row['reason'] = 'BOUND'
        self.assertTrue(native.live_matches([row], native.DEFAULT))

    def test_static_lease_cannot_confirm_automatic_addressing(self):
        row = dict(interface='eth0', if_up='true', reason='STATIC',
                   new_ip_address='192.0.2.8', new_subnet_cidr='24')
        self.assertFalse(native.live_matches([row], native.DEFAULT))
        wanted = {**native.DEFAULT, **native.changes('address', ['192.0.2.8/24', 'none'])}
        self.assertTrue(native.live_matches([row], wanted))
        wanted.update(native.changes('dns', ['192.0.2.53']))
        self.assertFalse(native.live_matches([row], wanted))


class Recovery(unittest.TestCase):
    def setUp(self):
        self.before = 'option domain_name_servers\n'
        self.new = 'interface eth0\nstatic domain_name_servers=192.0.2.53\n'
        self.after = self.before + self.new
        self.current = self.before
        self.records = []
        self.rebinds = []
        def write(before, after, info):
            self.assertEqual(self.current, before)
            self.current = after
        mocks = {'read_config': lambda: (self.current, None),
                 'owner': lambda *args: (123, []),
                 'replace_config': write,
                 'rebind': lambda *args: self.rebinds.append(args),
                 'write_record': lambda token, record: self.records.append(record.copy())}
        for name, method in mocks.items():
            p = patch.object(native, name, method)
            p.start()
            self.addCleanup(p.stop)

    def apply(self):
        return native.transaction('eth0', self.before, self.after, '', self.new,
                                  native.DEFAULT, 123, 1000)

    def test_native_failure_restores_prior_config_and_confirms_recovery(self):
        with patch.object(native, 'await_live', side_effect=[native.Refused('failed'), None]):
            with self.assertRaisesRegex(native.Refused, 'prior native network settings restored'):
                self.apply()
        self.assertEqual(self.current, self.before)
        self.assertEqual(len(self.rebinds), 2)
        self.assertFalse(any(r['ready'] for r in self.records))

    def test_later_edit_wins_during_failure(self):
        def external(*args):
            self.current += '# native editor\n'
            raise native.Refused('failure')
        with patch.object(native, 'await_live', external):
            with self.assertRaisesRegex(native.Refused, 'inspect them before recovery'):
                self.apply()
        self.assertEqual(self.current, self.after + '# native editor\n')
        self.assertEqual(len(self.rebinds), 1)
        self.assertFalse(any(r['ready'] for r in self.records))

    def test_success_records_only_target_section_and_config_digest(self):
        with patch.object(native, 'await_live', return_value=None):
            result = self.apply()
        self.assertEqual(len(result['undo']), 64)
        self.assertTrue(self.records[-1]['ready'])
        self.assertEqual(self.records[-1]['before'], '')
        self.assertEqual(self.records[-1]['after'], self.new)
        self.assertEqual(self.records[-1]['expected'], native.digest(self.after))
        self.assertNotIn(self.before, str(self.records))


if __name__ == '__main__':
    unittest.main()
