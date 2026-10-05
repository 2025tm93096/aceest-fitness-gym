import os
import tempfile
import pytest
from app.app import app as flask_app, init_db


@pytest.fixture
def client():
    db_fd, db_path = tempfile.mkstemp()
    flask_app.config["TESTING"] = True
    flask_app.DB_NAME = db_path
    os.environ["ACEEST_DB"] = db_path

    with flask_app.app_context():
        init_db()

    with flask_app.test_client() as test_client:
        yield test_client

    os.close(db_fd)
    if os.path.exists(db_path):
        os.unlink(db_path)
