#!/usr/bin/env python3
import os
import sys
import json
import time
import subprocess
import tempfile
import shutil

def run_tests():
    temp_dir = tempfile.mkdtemp(prefix="test_notch_hud_")
    try:
        script_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        dispatcher_py = os.path.join(script_dir, "dispatcher.py")

        # Copy dispatcher.py and dummy config into temp_dir
        temp_dispatcher = os.path.join(temp_dir, "dispatcher.py")
        shutil.copy(dispatcher_py, temp_dispatcher)
        os.chmod(temp_dispatcher, 0o755)

        with open(os.path.join(temp_dir, "config.json"), "w") as f:
            json.dump({
                "notifications": {"approval_timeout_seconds": 5, "enable_notch_popup": False},
                "audio": {"sound_enabled": False},
                "auto_approve": {"enabled": False}
            }, f)

        # 1. Create a dummy artifact and metadata file
        art_path = os.path.join(temp_dir, "my_feature_plan.md")
        with open(art_path, "w") as f:
            f.write("# Feature Plan\n\nSome content")

        meta_path = art_path + ".metadata.json"
        with open(meta_path, "w") as f:
            json.dump({
                "summary": "Original summary",
                "requestFeedback": True,
                "userFacing": True,
                "updatedAt": "2026-10-30T10:00:00Z"
            }, f)

        # 2. Run update_artifacts_state via stop hook or python import
        sys.path.insert(0, temp_dir)
        import dispatcher

        dispatcher.update_artifacts_state(temp_dir, artifact_dir=temp_dir, target_file=art_path)

        state_dir = os.path.join(temp_dir, "state")
        artifacts_json_path = os.path.join(state_dir, "artifacts.json")
        session_json_path = os.path.join(state_dir, "session.json")

        assert os.path.exists(artifacts_json_path), "artifacts.json should exist"
        with open(artifacts_json_path, "r") as f:
            arts = json.load(f)
        assert len(arts) == 1
        assert arts[0]["status"] == "pending_review", f"Expected pending_review, got {arts[0]['status']}"
        assert arts[0]["requestFeedback"] is True

        assert os.path.exists(session_json_path), "session.json should exist"
        with open(session_json_path, "r") as f:
            sess = json.load(f)
        assert sess["status"] == "waiting_review", f"Expected waiting_review, got {sess['status']}"
        assert sess["pendingReview"] is True

        # 3. Call dispatcher.approve_artifact (or python3 dispatcher.py --approve-artifact)
        res = subprocess.run([sys.executable, temp_dispatcher, "--approve-artifact", art_path],
                             cwd=temp_dir, capture_output=True, text=True)
        assert res.returncode == 0, f"Approval command failed: {res.stderr}"
        res_data = json.loads(res.stdout)
        assert res_data.get("status") == "approved"
        assert res_data.get("decision") == "allow"

        # 4. Verify metadata was updated
        with open(meta_path, "r") as f:
            meta = json.load(f)
        assert meta["requestFeedback"] is False, "requestFeedback should be False"
        assert meta["approved"] is True, "approved should be True"
        assert meta["userApproved"] is True, "userApproved should be True"
        assert meta["status"] == "approved", "status should be approved"

        # 5. Verify state/artifacts.json was updated
        with open(artifacts_json_path, "r") as f:
            updated_arts = json.load(f)
        assert updated_arts[0]["status"] == "reviewed", f"Expected reviewed, got {updated_arts[0]['status']}"
        assert updated_arts[0]["requestFeedback"] is False
        assert updated_arts[0]["approved"] is True

        # 6. Verify state/session.json was updated
        with open(session_json_path, "r") as f:
            updated_sess = json.load(f)
        assert updated_sess["status"] == "active", f"Expected active, got {updated_sess['status']}"
        assert updated_sess["unblocked"] is True
        assert updated_sess["pendingReview"] is False

        # 7. Verify state/decision.json was created
        decision_json_path = os.path.join(state_dir, "decision.json")
        assert os.path.exists(decision_json_path), "decision.json should exist"
        with open(decision_json_path, "r") as f:
            dec = json.load(f)
        assert dec["decision"] == "allow"
        assert dec["action"] == "proceed"

        # 8. Test that subsequent update_artifacts_state does NOT revert to pending_review
        dispatcher.update_artifacts_state(temp_dir, artifact_dir=temp_dir)
        with open(artifacts_json_path, "r") as f:
            recheck_arts = json.load(f)
        assert recheck_arts[0]["status"] == "reviewed", "Should remain reviewed after rescanning directory"
        assert recheck_arts[0]["requestFeedback"] is False

        with open(session_json_path, "r") as f:
            recheck_sess = json.load(f)
        assert recheck_sess["status"] == "active", "Session should remain active"
        assert recheck_sess["pendingReview"] is False

        print("✅ [test_dispatcher_artifacts] All dispatcher integration tests passed cleanly!")

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

if __name__ == "__main__":
    run_tests()
