#!/bin/bash
unset VIRTUAL_ENV
unset VENV
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin"
cd /root/.cline/data/workspaces/chat/enginscan
dart test test/simple_test_runner_test.dart test/quick_commands_screen_test.dart --reporter=expanded 2>&1
echo "EXIT_CODE=$?"
