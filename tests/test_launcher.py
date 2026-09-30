"""Disposable host process/PTY fixtures; never address real Kobo services."""

import os
from pathlib import Path
import pty
import signal
import shlex
import subprocess
import tempfile
import termios
import time
import unittest
import json
import sys


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"


class LauncherTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="xcsoar-launcher-")
        self.root = Path(self.temp.name)
        self.app = self.root / "app"
        self.app.mkdir()
        self.session = self.root / "session"
        self.data = self.root / "data"
        self.shims = self.root / "shims"
        self.shims.mkdir()
        self.processes = []
        self.shell = shlex.split(os.environ.get("XCSOAR_TEST_SHELL", "sh"))
        self.env = dict(os.environ, XCSOAR_APPDIR=str(self.app),
                        XCSOAR_DATADIR=str(self.data),
                        XCSOAR_SESSION_DIR=str(self.session), XCSOAR_GNSS="off",
                        PATH=str(self.shims) + ":" + os.environ["PATH"])
        self.pidof({})
        (self.app / "default-kobo-gnss.prf").write_text(
            'PortPath="/dev/ttyS0"\nPortBaudRate="9600"\nPortEnabled="1"\n')
        self.program('echo "$*" > args\nexec sleep 120\n')

    def tearDown(self):
        subprocess.run(self.shell + [str(SCRIPTS / "xcsoar-stop.sh")], env=self.env,
                       timeout=20, check=False)
        for process in self.processes:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)
        self.temp.cleanup()

    def pidof(self, names):
        # This shim cannot return any PID outside this test's own fixtures.
        script = "#!/bin/sh\ncase $1 in\n"
        for name, pid in names.items():
            script += f"{name}) echo {pid} ;;\n"
        script += "*) exit 1 ;;\nesac\n"
        path = self.shims / "pidof"
        path.write_text(script)
        path.chmod(0o755)

    def program(self, body):
        path = self.app / "xcsoar"
        path.write_text("#!/bin/sh\n" + body)
        path.chmod(0o755)

    def spawn(self, command, **kwargs):
        process = subprocess.Popen(command, **kwargs)
        self.processes.append(process)
        return process

    def run_supervisor(self):
        return self.spawn(self.shell + [str(SCRIPTS / "xcsoar-run.sh"), "--supervisor"],
                          env=self.env, stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL)

    def until(self, condition):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if condition():
                return
            time.sleep(0.02)
        self.fail("fixture condition timed out")

    def started(self):
        self.until(lambda: (self.session / "child").exists()
                   and (self.app / "args").exists())

    def stop(self):
        subprocess.run(self.shell + [str(SCRIPTS / "xcsoar-stop.sh")], env=self.env,
                       check=True, timeout=20)

    @staticmethod
    def state(pid):
        return Path(f"/proc/{pid}/stat").read_text().rsplit(") ", 1)[1].split()[0]

    def test_duplicate_stop_and_simulator(self):
        process = self.run_supervisor()
        self.started()
        child = (self.session / "child").read_text()
        duplicate = self.run_supervisor()
        self.assertEqual(duplicate.wait(timeout=5), 0)
        self.assertEqual((self.session / "child").read_text(), child)
        self.assertEqual((self.app / "args").read_text().strip(), "-simulator")
        self.stop()
        self.assertEqual(process.wait(timeout=5), 143)
        self.assertFalse(self.session.exists())
        self.stop()

    def test_concurrent_launches(self):
        launches = [self.run_supervisor() for _ in range(8)]
        self.started()
        self.until(lambda: sum(p.poll() is None for p in launches) == 1)
        active = next(p for p in launches if p.poll() is None)
        self.stop()
        self.assertEqual(active.wait(timeout=5), 143)
        self.assertFalse(self.session.exists())

    def test_failure_resumes_only_our_processes(self):
        nickel = self.spawn(["sleep", "120"])
        stopped = self.spawn(["sleep", "120"])
        os.kill(stopped.pid, signal.SIGSTOP)
        self.until(lambda: self.state(stopped.pid) == "T")
        self.pidof({"nickel": nickel.pid, "sickel": stopped.pid})
        self.program("sleep 0.2\nexit 7\n")
        process = self.run_supervisor()
        self.assertEqual(process.wait(timeout=5), 7)
        self.assertNotEqual(self.state(nickel.pid), "T")
        self.assertEqual(self.state(stopped.pid), "T")
        self.assertFalse(self.session.exists())

    def test_stale_supervisor_recovery(self):
        nickel = self.spawn(["sleep", "120"])
        self.pidof({"nickel": nickel.pid})
        process = self.run_supervisor()
        self.started()
        child_pid = int((self.session / "child").read_text().split()[0])
        process.kill()
        process.wait(timeout=5)
        self.stop()
        self.assertFalse(self.session.exists())
        self.assertNotEqual(self.state(nickel.pid), "T")
        self.assertTrue(not Path(f"/proc/{child_pid}").exists() or
                        self.state(child_pid) == "Z")

    def test_reused_pid_is_never_signalled(self):
        innocent = self.spawn(["sleep", "120"])
        fields = Path(f"/proc/{innocent.pid}/stat").read_text().rsplit(") ", 1)[1].split()
        self.session.mkdir()
        identity = f"{innocent.pid} {int(fields[19]) + 1}\n"
        for name in ("supervisor", "child", "nickel", "serial-owner"):
            (self.session / name).write_text(identity)
        self.stop()
        self.assertIsNone(innocent.poll())
        self.assertFalse(self.session.exists())

    def test_stale_session_recovered_by_launch(self):
        old = self.run_supervisor()
        self.started()
        old_child = (self.session / "child").read_text()
        old.kill()
        old.wait(timeout=5)
        (self.app / "args").unlink()
        new = self.run_supervisor()
        self.started()
        self.assertNotEqual((self.session / "child").read_text(), old_child)
        self.stop()
        self.assertEqual(new.wait(timeout=5), 143)

    def test_failed_uart_restore_retains_recovery_state(self):
        serial_owner = self.spawn(["sleep", "120"])
        os.kill(serial_owner.pid, signal.SIGSTOP)
        self.until(lambda: self.state(serial_owner.pid) == "T")
        fields = Path(f"/proc/{serial_owner.pid}/stat").read_text().rsplit(") ", 1)[1].split()
        self.session.mkdir()
        (self.session / "serial-owner").write_text(f"{serial_owner.pid} {fields[19]}\n")
        (self.session / "tty").write_text("/nonexistent/saved-uart\n0:0\ninvalid\n")
        result = subprocess.run(self.shell + [str(SCRIPTS / "xcsoar-stop.sh")],
                                env=self.env, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.session / "tty").exists())
        self.assertEqual(self.state(serial_owner.pid), "T")
        # Remove only the deliberately invalid fixture to permit tearDown.
        (self.session / "tty").unlink()

    def test_existing_profile_preserved(self):
        self.data.mkdir()
        profile = self.data / "default.prf"
        original = 'PortPath="/dev/custom"\nUserSetting="keep"\n'
        profile.write_text(original)
        self.program("exit 0\n")
        self.assertEqual(self.run_supervisor().wait(timeout=5), 0)
        self.assertEqual(profile.read_text(), original)

    def test_missing_uart_fails_before_suspending_nickel(self):
        nickel = self.spawn(["sleep", "120"])
        self.pidof({"nickel": nickel.pid})
        self.env.update(XCSOAR_GNSS="on", GNSS_SERIAL_PORT="/nonexistent/uart")
        self.assertNotEqual(self.run_supervisor().wait(timeout=5), 0)
        self.assertNotEqual(self.state(nickel.pid), "T")
        self.assertFalse(self.session.exists())

    def test_termios_restored_on_same_uart(self):
        master, slave = pty.openpty()
        try:
            path = os.ttyname(slave)
            before = termios.tcgetattr(master)
            os.close(slave)
            slave = None
            self.env.update(XCSOAR_GNSS="on", GNSS_SERIAL_PORT=path)
            self.program('echo "$*" > args\nstty -F "$GNSS_SERIAL_PORT" raw 19200\nexec sleep 120\n')
            process = self.run_supervisor()
            self.started()
            self.until(lambda: termios.tcgetattr(master) != before)
            # Recovery uses the saved UART, even with a different stop environment.
            self.env["GNSS_SERIAL_PORT"] = "/nonexistent/other"
            self.stop()
            process.wait(timeout=5)
            self.assertEqual(termios.tcgetattr(master), before)
            self.assertFalse(self.session.exists())
        finally:
            if slave is not None:
                os.close(slave)
            os.close(master)

    def test_unknown_uart_owner_is_not_killed(self):
        master, slave = pty.openpty()
        try:
            path = os.ttyname(slave)
            owner = self.spawn(["sleep", "120"], pass_fds=(slave,))
            os.close(slave)
            slave = None
            self.env.update(XCSOAR_GNSS="on", GNSS_SERIAL_PORT=path)
            self.assertNotEqual(self.run_supervisor().wait(timeout=10), 0)
            self.assertIsNone(owner.poll())
            self.assertFalse(self.session.exists())
        finally:
            if slave is not None:
                os.close(slave)
            os.close(master)

    def getty_lifecycle(self, wrapper_name="start_getty", exit_mode="stop"):
        master, slave = pty.openpty()
        fixture = None
        try:
            port = os.ttyname(slave)
            before = termios.tcgetattr(master)
            os.close(slave)
            slave = None
            state_path = self.root / "getty-state.json"
            fixture = self.spawn(
                [sys.executable, str(Path(__file__).with_name("getty_fixture.py")),
                 wrapper_name, port, str(state_path), "getty"],
                start_new_session=True)
            self.until(state_path.exists)
            first = json.loads(state_path.read_text())
            self.env.update(XCSOAR_GNSS="on", GNSS_SERIAL_PORT=port)
            self.program('echo "$*" > args\nstty -F "$GNSS_SERIAL_PORT" raw 19200\n'
                         'while [ ! -f exit-child ]; do sleep 0.05; done\nexit 7\n')
            supervisor = self.run_supervisor()
            self.started()
            self.until(lambda: termios.tcgetattr(master) != before)
            self.assertEqual(self.state(first["wrapper"]), "T")
            self.assertTrue(not Path(f'/proc/{first["getty"]}').exists() or
                            self.state(first["getty"]) == "Z")
            self.assertEqual(json.loads(state_path.read_text())["generation"], 1)
            if exit_mode == "failure":
                (self.app / "exit-child").touch()
                self.assertEqual(supervisor.wait(timeout=5), 7)
            elif exit_mode == "crash":
                supervisor.kill()
                supervisor.wait(timeout=5)
                self.stop()
            else:
                self.stop()
                self.assertEqual(supervisor.wait(timeout=5), 143)
            self.until(lambda: json.loads(state_path.read_text())["generation"] == 2)
            resumed = json.loads(state_path.read_text())
            self.assertEqual(resumed["termios"], before[:6])
            self.assertEqual(termios.tcgetattr(master), before)
            self.assertNotEqual(self.state(resumed["wrapper"]), "T")
            self.assertFalse(self.session.exists())
        finally:
            # Every descendant belongs to this fixture's private process group.
            if fixture is not None:
                os.killpg(fixture.pid, signal.SIGKILL)
                fixture.wait(timeout=5)
            if slave is not None:
                os.close(slave)
            os.close(master)

    def test_start_getty_takeover_and_respawn(self):
        self.getty_lifecycle()

    def test_start_getty_child_failure_restores_console(self):
        self.getty_lifecycle(exit_mode="failure")

    def test_start_getty_supervisor_crash_restores_console(self):
        self.getty_lifecycle(exit_mode="crash")

    def test_legacy_getty_takeover_and_respawn(self):
        self.getty_lifecycle(wrapper_name="kobo_getty.sh")


if __name__ == "__main__":
    unittest.main()
