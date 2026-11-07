"""Property-based (fuzz) tests for image/render_config.py.

The rendered file is read back the same way virt-who reads its configuration,
so any accepted value must survive the round trip unchanged.
"""

import os
import sys
from configparser import ConfigParser
from pathlib import Path
from unittest import mock

import pytest
from hypothesis import example, given
from hypothesis import strategies as st

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "image"))

import render_config

REQUIRED = {
    "SATELLITE_ORG": "owner",
    "SATELLITE_HOST": "rhsm_hostname",
    "RHSM_USERNAME": "rhsm_username",
    "RHSM_PASSWORD": "rhsm_password",
}
OPTIONAL = {
    "HYPERVISOR_ID": "hypervisor_id",
    "LIBVIRT_SERVER": "server",
    "SATELLITE_PREFIX": "rhsm_prefix",
}


class StripQuotesConfigParser(ConfigParser):
    """Mirror of virtwho.config.StripQuotesConfigParser (virt-who 1.32)."""

    def get(self, section, option, **kwargs):  # type: ignore[override]
        value = ConfigParser.get(self, section, option, **kwargs)
        for quote in ('"', "'"):
            if value.startswith(quote) and value.endswith(quote) and quote not in value[1:-1]:
                return value.strip(quote)
        return value


def parse(content: str, tmp_path: Path) -> StripQuotesConfigParser:
    # virt-who reads the file from disk, so go through a real file.
    path = tmp_path / "libvirt.conf"
    path.write_text(content, encoding="utf-8")
    parser = StripQuotesConfigParser(strict=True)
    parser.read(path, encoding="utf-8")
    return parser


# Environment values cannot contain NUL bytes or lone surrogates.
env_text = st.text(st.characters(exclude_categories=("Cs",), exclude_characters="\x00"), min_size=1)


@given(env_text)
@example('"')
@example("'")
@example('"quoted"')
@example('"a"b"')
@example("100%")
@example("%(owner)s")
@example("a\x85b")
@example("a\u2028b")
def test_ini_value_round_trips_or_is_rejected(tmp_path_factory, value):
    try:
        escaped = render_config.ini_value("rhsm_password", value)
    except ValueError:
        return
    parser = parse(f"[libvirt]\nrhsm_password={escaped}\n", tmp_path_factory.mktemp("cfg"))
    assert parser.get("libvirt", "rhsm_password") == value


@given(
    required=st.fixed_dictionaries({name: env_text for name in REQUIRED}),
    optional=st.fixed_dictionaries({}, optional={name: env_text for name in OPTIONAL}),
    port=st.one_of(st.none(), st.integers(1, 65535).map(str), st.text(max_size=8)),
)
def test_render_round_trips_or_is_rejected(tmp_path_factory, required, optional, port):
    environ = {**required, **optional}
    if port is not None and "\x00" not in port:
        environ["SATELLITE_PORT"] = port

    with mock.patch.dict(os.environ, environ, clear=True):
        try:
            content = render_config.render()
        except ValueError:
            return

    parser = parse(content, tmp_path_factory.mktemp("cfg"))
    assert parser.sections() == ["libvirt"]
    section = parser["libvirt"]
    assert parser.get("libvirt", "type") == "libvirt"
    for name, key in {**REQUIRED, **OPTIONAL}.items():
        if name in environ:
            assert parser.get("libvirt", key) == environ[name]
    assert 1 <= int(section["rhsm_port"]) <= 65535


@pytest.mark.parametrize("name", sorted(REQUIRED))
def test_render_requires_settings(name):
    environ = dict.fromkeys(REQUIRED, "value")
    del environ[name]
    with (
        mock.patch.dict(os.environ, environ, clear=True),
        pytest.raises(ValueError, match=name),
    ):
        render_config.render()


def test_secret_files_are_read(tmp_path):
    secret = tmp_path / "password"
    secret.write_text("s3cr%t\n", encoding="utf-8")
    environ = dict.fromkeys(REQUIRED, "value")
    del environ["RHSM_PASSWORD"]
    environ["RHSM_PASSWORD_FILE"] = str(secret)
    with mock.patch.dict(os.environ, environ, clear=True):
        content = render_config.render()
    assert parse(content, tmp_path).get("libvirt", "rhsm_password") == "s3cr%t"
