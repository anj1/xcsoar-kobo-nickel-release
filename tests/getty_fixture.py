"""An isolated init -> foreground wrapper -> UART owner process fixture."""

import ctypes
import json
import os
from pathlib import Path
import signal
import sys
import termios


def name_process(name):
    if ctypes.CDLL(None).prctl(15, name.encode(), 0, 0, 0) != 0:
        raise RuntimeError("cannot set fixture process name")


def main():
    wrapper_name, port, state_path, owner_name = sys.argv[1:]
    name_process("fixture_init")
    generation = 0
    while True:
        generation += 1
        wrapper = os.fork()
        if wrapper == 0:
            name_process(wrapper_name)
            getty = os.fork()
            if getty == 0:
                name_process(owner_name)
                fd = os.open(port, os.O_RDWR | os.O_NOCTTY)
                state = Path(state_path)
                temporary = state.with_suffix(".tmp")
                temporary.write_text(json.dumps({
                    "wrapper": os.getppid(), "getty": os.getpid(),
                    "generation": generation, "termios": termios.tcgetattr(fd)[:6],
                }))
                temporary.replace(state)
                while True:
                    signal.pause()
            os.waitpid(getty, 0)
            os._exit(0)
        # Just as init's respawn entry, start a new wrapper after it exits.
        os.waitpid(wrapper, 0)


if __name__ == "__main__":
    main()
