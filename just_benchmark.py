import logging
import os
import re
import shutil
import subprocess
import urllib.request
from argparse import ArgumentParser
from pathlib import Path
from subprocess import CalledProcessError
from typing import Sequence, Optional


class Settings:
    install_directory: str
    proxy_host: str
    proxy_port: int
    php_executable: str

    def proxy_as_dist(self):
        return {"http": f"http://{self.proxy_host}:{self.proxy_port}"}


def get_root_dir() -> Path:
    return Path(__file__).parent.resolve()


def run(invocation: Sequence[str], *args, **kwargs):
    invocation = [str(item) for item in invocation]
    logging.info(f"> {' '.join(invocation)}")
    return subprocess.check_call(invocation, *args, **kwargs)


class InstallManager:

    def download_and_extract_archive(self, source_url, archive_file):
        archive_path = get_root_dir().joinpath(archive_file)
        if not archive_path.exists():
            logging.info(f"Downloading {source_url}...")
            urllib.request.urlretrieve(source_url, filename=archive_path)
        else:
            logging.info(f"Skipping download of {archive_file}, file exists.")

        logging.info(f"Extracting {archive_file}...")
        run(["tar", "-xf", archive_file, "--skip-old-files"], cwd=get_root_dir())

    def check_executable_on_path(self, cmd: str) -> Optional[Path]:
        try:
            php_path = subprocess.check_output(["which", cmd])
            return Path(php_path.decode().strip())
        except CalledProcessError:
            return None

    def check_executable_at_location(self, exe_path: Path, test_arg="--version") -> Optional[Path]:
        if exe_path.exists():
            try:
                subprocess.check_output([exe_path, test_arg])
                return exe_path
            except CalledProcessError:
                return None

    def check_shared_object_available_ldconfig(self, shared_object: str) -> Optional[Path]:
        output = subprocess.check_output(["ldconfig", "-p"]).decode()
        for line in output.splitlines():
            match = re.match(f"\s*{shared_object}.*=>\s*(/.*{shared_object})", line)
            if match:
                return Path(match.group(1))

    def install(self):
        raise NotImplementedError("Cannot install, missing override")

    def detect(self):
        raise NotImplementedError("Cannot detect install manager presence, missing override")

    @property
    def install_dir(self):
        raise NotImplementedError("Install directory not configured")

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

    def run_make(self, cwd=None, target=None):
        if cwd is None:
            cwd = self.install_dir
        cpu_count = os.cpu_count() or 1
        invocation = ["make", "-j", cpu_count]
        if target is not None:
            invocation.append(target)
        run(invocation, cwd=cwd)

    def check_shared_object_at_location(self, shared_object_path: Path):
        if shared_object_path.exists():
            return shared_object_path
        return None


class CMakeInstallManager(InstallManager):

    def detect(self):
        return self.check_executable_on_path("cmake") or self.check_executable_at_location(self.install_dir.joinpath("bin").joinpath("cmake"))

    def install(self):
        self.download_and_extract_archive(
            "https://github.com/Kitware/CMake/releases/download/v3.25.3/cmake-3.25.3-linux-x86_64.tar.gz",
            "cmake-3.25.3-linux-x86_64.tar.gz")

    @property
    def install_dir(self):
        return get_root_dir().joinpath("cmake-3.25.3-linux-x86_64")

    @property
    def name(self):
        return "CMake"

class InstallManagerCMake(InstallManager):

    @property
    def build_dir(self):
        return self.install_dir.joinpath("build")

    @property
    def cmake_install_dir(self):
        return self.install_dir.joinpath("install")


class LibZipInstallManager(InstallManagerCMake):

    def install(self):
        self.download_and_extract_archive(
            "https://github.com/nih-at/libzip/releases/download/v1.9.2/libzip-1.9.2.tar.gz", "libzip-1.9.2.tar.gz"
        )
        self.build_dir.mkdir(exist_ok=True)
        run(["cmake", "..", "-DBUILD_TOOLS=OFF", "-DBUILD_REGRESS=OFF", "-DBUILD_EXAMPLES=OFF", "-DBUILD_DOC=OFF",
             f"-DCMAKE_INSTALL_PREFIX={self.cmake_install_dir}"],
            cwd=self.build_dir)
        self.run_make(cwd=self.build_dir)
        self.run_make(cwd=self.build_dir, target="install")

    def detect(self):
        return self.check_shared_object_available_ldconfig("libzip.so") or self.check_shared_object_at_location(
            self.cmake_install_dir.joinpath("lib").joinpath("libzip.so")
        )

    @property
    def install_dir(self):
        return get_root_dir().joinpath("libzip-1.9.2")

    @property
    def name(self):
        return "LibZIP"


class PHPInstallManager(InstallManager):

    def install(self):
        self.download_and_extract_archive("https://www.php.net/distributions/php-7.4.33.tar.gz", "php-7.4.33.tar.gz")
        run(["./configure", "--with-zip", "--without-iconv", "--without-sqlite3", "--without-pdo-sqlite"],
            cwd=self.install_dir)
        self.run_make()

    def detect(self):
        local_php_location = self.install_dir.joinpath("sapi").joinpath("cli").joinpath("php")
        return self.check_executable_on_path("php") or self.check_executable_at_location(local_php_location)

    @property
    def install_dir(self):
        return get_root_dir().joinpath("php-7.4.33")

    @property
    def name(self):
        return "PHP"


class PTSInstallManager(InstallManager):

    def install(self):
        self.download_and_extract_archive(
            "https://phoronix-test-suite.com/releases/phoronix-test-suite-10.8.4.tar.gz",
            "phoronix-test-suite-10.8.4.tar.gz"
        )

    def detect(self):
        local_pts_location = self.install_dir.joinpath("phoronix-test-suite")
        return self.check_executable_on_path("phoronix-test-suite") or self.check_executable_at_location(
            local_pts_location, test_arg="system-info")

    @property
    def install_dir(self):
        return get_root_dir().joinpath("phoronix-test-suite")

    @property
    def name(self):
        return "Phoronix Test Suite"


def provide_pts():
    root_directory = get_root_dir()

    cmake_manager = CMakeInstallManager()
    cmake = cmake_manager.provide()
    os.environ["PATH"] = os.environ["PATH"] + ":" + str(cmake.parent)

    libzip_manager = LibZipInstallManager()
    libzip_manager.provide()

    os.environ["PKG_CONFIG_PATH"] = (
            os.environ.setdefault("PKG_CONFIG_PATH", "")
            + ":" + str(libzip_manager.cmake_install_dir.joinpath("lib").joinpath("pkgconfig"))
    )
    logging.info(f"Set PKG_CONFIG_PATH={os.environ['PKG_CONFIG_PATH']}")

    php_manager = PHPInstallManager()
    php_location = php_manager.provide()

    os.environ["PATH"] = os.environ["PATH"] + ":" + str(php_location.parent)

    pts_manager = PTSInstallManager()
    pts_location = pts_manager.provide()

    return pts_location


def batch_benchmark(pts_location: Path):
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


def shell(pts_location: Path):
    run(
        [pts_location, 'shell']
    )


if __name__ == '__main__':
    logging.basicConfig(format="%(message)s", level=logging.INFO)
    parser = ArgumentParser(description="Tool to bootstrap Phoronix Test Suite to simplify benchmarking.")

    subparsers = parser.add_subparsers(
        help="Choose what to do after bootstrapping Phoronix Test Suite"
    )

    shell_command = subparsers.add_parser(
        "shell",
        help="Launch the Phoronix Test Suite shell after bootstrapping.",
    )
    shell_command.set_defaults(handler=shell)

    batch_benchmark_command = subparsers.add_parser(
        "batch_benchmark",
        help="Run a benchmark or suite in batch mode. Takes care of various preliminary setup as well.",
    )
    batch_benchmark_command.set_defaults(handler=batch_benchmark)

    options_result = parser.parse_args()

    if options_result.handler is None:
        parser.print_help()
        exit(1)

    pts = provide_pts()
    options_result.handler(pts_location=pts)
