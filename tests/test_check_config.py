from pathlib import Path
import subprocess
import sys
import unittest


CHECKER = Path(__file__).resolve().parents[1] / "scripts" / "check-config.py"
VALID_CONFIG = {
    "TCONNECT_EMAIL": "dummy@example.invalid",
    "TCONNECT_PASSWORD": "dummy-password-not-a-credential",
    "TCONNECT_REGION": "US",
    "NS_URL": "https://nightscout.example.invalid",
    "NS_SECRET": "dummy-secret-not-a-credential",
    "TIMEZONE_NAME": "Etc/UTC",
}


class CheckConfigTests(unittest.TestCase):
    def run_checker(self, config):
        return subprocess.run(
            [sys.executable, str(CHECKER)],
            env=config,
            capture_output=True,
            check=False,
            text=True,
        )

    def test_accepts_valid_dummy_configuration_without_network(self):
        result = self.run_checker(VALID_CONFIG)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("no network connections were made", result.stdout)
        self.assertNotIn(VALID_CONFIG["TCONNECT_PASSWORD"], result.stdout + result.stderr)
        self.assertNotIn(VALID_CONFIG["NS_SECRET"], result.stdout + result.stderr)

    def test_example_contains_expected_configuration_names(self):
        example = CHECKER.parents[1] / "config" / "tconnectsync.env.example"
        lines = example.read_text().splitlines()
        names = {line.partition("=")[0] for line in lines if line and not line.startswith("#")}
        self.assertEqual(
            names,
            {
                "TCONNECT_EMAIL",
                "TCONNECT_PASSWORD",
                "TCONNECT_REGION",
                "NS_URL",
                "NS_SECRET",
                "TIMEZONE_NAME",
            },
        )
        self.assertIn("# PUMP_SERIAL_NUMBER=", lines)

    def test_reports_missing_required_configuration(self):
        result = self.run_checker({})
        self.assertNotEqual(result.returncode, 0)
        for name in ("TCONNECT_EMAIL", "TCONNECT_PASSWORD", "NS_URL", "NS_SECRET", "TIMEZONE_NAME"):
            self.assertIn(name, result.stderr)

    def test_rejects_invalid_region(self):
        config = {**VALID_CONFIG, "TCONNECT_REGION": "CA"}
        self.assertIn("TCONNECT_REGION", self.run_checker(config).stderr)

    def test_rejects_invalid_url_timezone_and_serial(self):
        cases = (
            ({"NS_URL": "not-a-url"}, "NS_URL"),
            ({"TIMEZONE_NAME": "Not/A_Timezone"}, "TIMEZONE_NAME"),
            ({"PUMP_SERIAL_NUMBER": "12x"}, "PUMP_SERIAL_NUMBER"),
        )
        for overrides, expected_error in cases:
            with self.subTest(expected_error=expected_error):
                result = self.run_checker({**VALID_CONFIG, **overrides})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(expected_error, result.stderr)


if __name__ == "__main__":
    unittest.main()
