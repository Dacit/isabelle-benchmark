import logging
import os
import shutil
import subprocess
import urllib.request
from argparse import ArgumentParser
from dataclasses import dataclass
from subprocess import CalledProcessError

from pathlib import Path
from typing import Sequence


@dataclass
class Settings:
    install_directory: str
    proxy_host: str
    proxy_port: int
    php_executable: str

    def proxy_as_dist(self):
        return { "http": f"http://{self.proxy_host}:{self.proxy_port}"}

def get_root_dir() -> Path:
    return Path(__file__).parent.resolve()


def run(invocation: Sequence[str], *args, **kwargs):
    invocation = [str(item) for item in invocation]
    logging.info(f"> {' '.join(invocation)}")
    return subprocess.check_call(invocation, *args, **kwargs)


@dataclass
class InstallManager:
    install_dir: Path

    def download_and_extract_archive(self, source_url, archive_file):
        archive_path = get_root_dir().joinpath(archive_file)
        if not archive_path.exists():
            logging.info(f"Downloading {source_url}...")
            urllib.request.urlretrieve(source_url, filename=archive_path)
        else:
            logging.info(f"Skipping download of {archive_file}, file exists.")

        logging.info(f"Extracting {archive_file}...")
        run(["tar", "-xf", archive_file], cwd=get_root_dir())

    def check_executable_on_path(self, cmd: str):
        try:
            php_path = subprocess.check_output(["which", cmd])
            return php_path.decode().strip()
        except CalledProcessError:
            return None

    def check_executable_at_location(self, exe_path: Path, test_arg="--version"):
        if exe_path.exists():
            try:
                subprocess.check_output([exe_path, test_arg])
                return exe_path
            except CalledProcessError:
                return None

    def install(self):
        raise NotImplementedError("Cannot install, missing override")

    def detect(self):
        raise NotImplementedError("Cannot detect install manager presence, missing override")

    @property
    def name(self):
        return "Install Manager"

    def provide(self) -> Path:
        location = self.detect()
        if location is None:
            logging.info(f"No {self.name} detected. Installing to {self.install_dir}...")
            self.install()
            location = self.detect()
        if location is None:
            raise RuntimeError(f"Could not provide {self.name}")
        logging.info(f"Providing {self.name} using {location}")
        return location

    def uninstall(self):
        shutil.rmtree(self.install_dir)


@dataclass
class PHPInstallManager(InstallManager):

    def install(self):
        self.download_and_extract_archive("https://www.php.net/distributions/php-8.2.3.tar.gz", "php-8.2.3.tar.gz")
        run(["./configure", "--with-zip", "--without-iconv"], cwd=self.install_dir)
        cpu_count = os.cpu_count() or 1
        run(["make", "-j", cpu_count], cwd=self.install_dir)

    def detect(self):
        local_php_location = self.install_dir.joinpath("sapi").joinpath("cli").joinpath("php")
        return self.check_executable_on_path("php") or self.check_executable_at_location(local_php_location)

    @property
    def name(self):
        return "PHP"


@dataclass
class PTSInstallManager(InstallManager):

    def install(self):
        self.download_and_extract_archive(
            "https://phoronix-test-suite.com/releases/phoronix-test-suite-10.8.4.tar.gz", "phoronix-test-suite-10.8.4.tar.gz"
        )

    def detect(self):
        local_pts_location = self.install_dir.joinpath("phoronix-test-suite")
        return self.check_executable_on_path("phoronix-test-suite") or self.check_executable_at_location(local_pts_location, test_arg="system-info")

    @property
    def name(self):
        return "Phoronix Test Suite"


def run_phoronix_test_suite():
    root_directory = get_root_dir()
    php_manager = PHPInstallManager(install_dir=root_directory.joinpath("php-8.2.3"))
    php_location = php_manager.provide()

    os.environ["PATH"] = os.environ["PATH"] + ":" + str(php_location.parent)

    pts_manager = PTSInstallManager(install_dir=root_directory.joinpath("phoronix-test-suite"))
    pts_location = pts_manager.provide()

    run(
        [pts_location, 'network-setup'],
    )

    run(
        [pts_location, 'batch-setup'],
    )

    run(
        [pts_location, 'enable-repo', 'vinpasso'],
    )

    run(
        [pts_location, 'batch-benchmark', 'vinpasso/isabelle'],
    )

if __name__ == '__main__':
    logging.basicConfig(format="%(message)s", level=logging.INFO)
    parser = ArgumentParser(description="Tool to bootstrap Phoronix Test Suite to simplify benchmarking.")

    options_result = parser.parse_args()

    run_phoronix_test_suite()
