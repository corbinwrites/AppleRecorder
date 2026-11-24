#!/usr/bin/env bash
set -u
F="Packages/Capture/Sources/Capture/RealtimeCallback.swift"
BAD='print\(|NSLog|Logger|os_log|Task[ ]*\{|await |async |DispatchQueue|DispatchSemaphore|NSLock|OSAllocatedUnfairLock|Mutex|\.append\(|Array\(|String\(|malloc|try[ ?!]|throw |fatalError|precondition'
HITS=$(grep -v '^[[:space:]]*//' "$F" | grep -nE "$BAD")
if [ -n "$HITS" ]; then echo "FAIL realtime check:"; echo "$HITS"; exit 1; fi
echo "PASS realtime check"
