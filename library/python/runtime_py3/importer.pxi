import marshal
import sys
from _codecs import utf_8_decode, utf_8_encode
from _frozen_importlib import _call_with_frames_removed, spec_from_loader, BuiltinImporter
from _frozen_importlib_external import _os, _path_isfile, _path_isdir, path_sep, _path_join
from _io import FileIO

import __res as __resource

_b = lambda x: x if isinstance(x, bytes) else utf_8_encode(x)[0]
_s = lambda x: x if isinstance(x, str) else utf_8_decode(x)[0]
env_entry_point = b'Y_PYTHON_ENTRY_POINT'
env_source_root = b'Y_PYTHON_SOURCE_ROOT'
env_strict_source_search = b'Y_PYTHON_STRICT_SOURCE_SEARCH'
executable = sys.executable or 'Y_PYTHON'
sys.modules['run_import_hook'] = __resource

# This is the prefix in contrib/tools/python3/src/Lib/ya.make.
py_prefix = b'py/'
py_prefix_len = len(py_prefix)

Y_PYTHON_SOURCE_ROOT = _os.environ.get(env_source_root)
Y_PYTHON_STRICT_SOURCE_SEARCH = _os.environ.get(env_strict_source_search)


def _print(*xs):
    """
    This is helpful for debugging, since automatic bytes to str conversion is
    not available yet.  It is also possible to debug with GDB by breaking on
    __Pyx_AddTraceback (with Python GDB pretty printers enabled).
    """
    parts = []
    for s in xs:
        if not isinstance(s, (bytes, str)):
            s = str(s)
        parts.append(_s(s))
    sys.stderr.write(' '.join(parts) + '\n')


def file_bytes(path):
    # 'open' is not avaiable yet.
    with FileIO(path, 'r') as f:
        return f.read()


def iter_keys(prefix):
    l = len(prefix)
    for idx in range(__resource.count()):
        key = __resource.key_by_index(idx)
        if key.startswith(prefix):
            yield key, key[l:]


def iter_py_modules(with_keys=False):
    for key, path in iter_keys(b'resfs/file/' + py_prefix):
        if path.endswith(b'.py'):  # It may also end with '.pyc'.
            mod = _s(path[:-3].replace(b'/', b'.'))
            if with_keys:
                yield key, mod
            else:
                yield mod


def iter_prefixes(s):
    i = s.find('.')
    while i >= 0:
        yield s[:i]
        i = s.find('.', i + 1)


def resfs_resolve(path):
    """
    Return the absolute path of a root-relative path if it exists.
    """
    path = _b(path)
    if Y_PYTHON_SOURCE_ROOT:
        if not path.startswith(Y_PYTHON_SOURCE_ROOT):
            path = _b(path_sep).join((Y_PYTHON_SOURCE_ROOT, path))
        if _path_isfile(path):
            return path


def resfs_src(key, resfs_file=False):
    """
    Return the root-relative file path of a resource key.
    """
    if resfs_file:
        key = b'resfs/file/' + _b(key)
    return __resource.find(b'resfs/src/' + _b(key))


def resfs_read(path, builtin=None):
    """
    Return the bytes of the resource file at path, or None.
    If builtin is True, do not look for it on the filesystem.
    If builtin is False, do not look in the builtin resources.
    """
    if builtin is not True:
        arcpath = resfs_src(path, resfs_file=True)
        if arcpath:
            fspath = resfs_resolve(arcpath)
            if fspath:
                return file_bytes(fspath)

    if builtin is not False:
        return __resource.find(b'resfs/file/' + _b(path))


def resfs_files(prefix=b''):
    """
    List builtin resource file paths.
    """
    return [key[11:] for key, _ in iter_keys(b'resfs/file/' + _b(prefix))]


def mod_path(mod):
    """
    Return the resfs path to the source code of the module with the given name.
    """
    return py_prefix + _b(mod).replace(b'.', b'/') + b'.py'


class ResourceImporter(object):

    """ A meta_path importer that loads code from built-in resources.
    """

    def __init__(self):
        self.memory = set(iter_py_modules())  # Set of importable module names.
        self.source_map = {}                  # Map from file names to module names.
        self._source_name = {}                # Map from original to altered module names.
        self._package_prefix = ''
        if Y_PYTHON_SOURCE_ROOT and not Y_PYTHON_STRICT_SOURCE_SEARCH:
            self.arcadia_source_finder = ArcadiaSourceFinder(_s(Y_PYTHON_SOURCE_ROOT))
        else:
            self.arcadia_source_finder = None

        for p in list(self.memory) + list(sys.builtin_module_names):
            for pp in iter_prefixes(p):
                k = pp + '.__init__'
                if k not in self.memory:
                    self.memory.add(k)

    def for_package(self, name):
        import copy
        importer = copy.copy(self)
        importer._package_prefix = name + '.'
        return importer

    def _find_mod_path(self, fullname):
        """Find arcadia relative path by module name"""
        relpath = resfs_src(mod_path(fullname), resfs_file=True)
        if relpath or not self.arcadia_source_finder:
            return relpath
        return self.arcadia_source_finder.get_module_path(fullname)

    def find_spec(self, fullname, path=None, target=None):
        try:
            is_package = self.is_package(fullname)
        except ImportError:
            return None
        return spec_from_loader(fullname, self, is_package=is_package)

    def find_module(self, fullname, path=None):
        """For backward compatibility."""
        spec = self.find_spec(fullname, path)
        return spec.loader if spec is not None else None

    def create_module(self, spec):
        """Use default semantics for module creation."""

    def exec_module(self, module):
        code = self.get_code(module.__name__)
        module.__file__ = code.co_filename
        if self.is_package(module.__name__):
            module.__path__= [executable + path_sep + module.__name__.replace('.', path_sep)]
        # exec(code, module.__dict__)
        _call_with_frames_removed(exec, code, module.__dict__)

    # PEP-302 extension 1 of 3: data loader.
    def get_data(self, path):
        path = _b(path)
        abspath = resfs_resolve(path)
        if abspath:
            return file_bytes(abspath)
        path = path.replace(_b('\\'), _b('/'))
        data = resfs_read(path, builtin=True)
        if data is None:
            raise IOError(path)  # Y_PYTHON_ENTRY_POINT=:resource_files
        return data

    # PEP-302 extension 2 of 3: get __file__ without importing.
    def get_filename(self, fullname):
        modname = fullname
        if self.is_package(fullname):
            fullname += '.__init__'
        relpath = self._find_mod_path(fullname)
        if isinstance(relpath, bytes):
            relpath = _s(relpath)
        return relpath or modname

    # PEP-302 extension 3 of 3: packaging introspection.
    # Used by `linecache` (while printing tracebacks) unless module filename
    # exists on the filesystem.
    def get_source(self, fullname):
        fullname = self._source_name.get(fullname) or fullname
        if self.is_package(fullname):
            fullname += '.__init__'

        relpath = self.get_filename(fullname)
        if relpath:
            abspath = resfs_resolve(relpath)
            if abspath:
                return _s(file_bytes(abspath))
        data = resfs_read(mod_path(fullname))
        return _s(data) if data else ''

    def get_code(self, fullname):
        modname = fullname
        if self.is_package(fullname):
            fullname += '.__init__'

        path = mod_path(fullname)
        relpath = self._find_mod_path(fullname)
        if relpath:
            abspath = resfs_resolve(relpath)
            if abspath:
                data = file_bytes(abspath)
                return compile(data, _s(abspath), 'exec', dont_inherit=True)

        yapyc_path = path + b'.yapyc3'
        yapyc_data = resfs_read(yapyc_path, builtin=True)
        if yapyc_data:
            return marshal.loads(yapyc_data)
        else:
            py_data = resfs_read(path, builtin=True)
            if py_data:
                return compile(py_data, _s(relpath), 'exec', dont_inherit=True)
            else:
                # This covers packages with no __init__.py in resources.
                return compile('', modname, 'exec', dont_inherit=True)

    def is_package(self, fullname):
        if fullname in self.memory:
            return False

        if fullname + '.__init__' in self.memory:
            return True

        if self.arcadia_source_finder:
            return self.arcadia_source_finder.is_package(fullname)

        raise ImportError(fullname)

    # Extension for contrib/python/coverage.
    def file_source(self, filename):
        """
        Return the key of the module source by its resource path.
        """
        if not self.source_map:
            for key, mod in iter_py_modules(with_keys=True):
                path = self.get_filename(mod)
                self.source_map[path] = key

        if filename in self.source_map:
            return self.source_map[filename]

        if resfs_read(filename, builtin=True) is not None:
            return b'resfs/file/' + _b(filename)

        return b''

    # Extension for pkgutil.iter_modules.
    def iter_modules(self, prefix=''):
        import re
        rx = re.compile(re.escape(self._package_prefix) + r'([^.]+)(\.__init__)?$')
        for p in self.memory:
            m = rx.match(p)
            if m:
                yield prefix + m.group(1), m.group(2) is not None
        if self.arcadia_source_finder:
            for m in self.arcadia_source_finder.iter_modules(self._package_prefix, prefix):
                yield m

    def get_resource_reader(self, fullname):
        try:
            if not self.is_package(fullname):
                return None
        except ImportError:
            return None
        return _ResfsResourceReader(self, fullname)


class _ResfsResourceReader:

    def __init__(self, importer, fullname):
        self.importer = importer
        self.fullname = fullname

        import os
        self.prefix = "{}/".format(os.path.dirname(self.importer.get_filename(self.fullname)))

    def open_resource(self, resource):
        path = f'{self.prefix}{resource}'
        from io import BytesIO
        try:
            return BytesIO(self.importer.get_data(path))
        except OSError:
            raise FileNotFoundError(path)

    def resource_path(self, resource):
        # All resources are in the binary file, so there is no path to the file.
        # Raising FileNotFoundError tells the higher level API to extract the
        # binary data and create a temporary file.
        raise FileNotFoundError

    def is_resource(self, name):
        path = f'{self.prefix}{name}'
        try:
            self.importer.get_data(path)
        except OSError:
            return False
        return True

    def contents(self):
        subdirs_seen = set()
        for key in resfs_files(self.prefix):
            relative = key[len(self.prefix):]
            res_or_subdir, *other = relative.split(b'/')
            if not other:
                yield _s(res_or_subdir)
            elif res_or_subdir not in subdirs_seen:
                subdirs_seen.add(res_or_subdir)
                yield _s(res_or_subdir)


class BuiltinSubmoduleImporter(BuiltinImporter):
    @classmethod
    def find_spec(cls, fullname, path=None, target=None):
        if path is not None:
            return super().find_spec(fullname, None, target)
        else:
            return None


class ArcadiaSourceFinder:
    NAMESPACE_PREFIX = b'py/namespace/'
    PY_EXT = '.py'

    def __init__(self, source_root):
        self.source_root = source_root
        # key: module_name:
        # value:
        #   list of relative package paths - for a package
        #   relative module path - for a module
        #   None - module or package is not found
        self.module_path_cache = {}
        self.namespace_paths = {}
        for key, dirty_path in iter_keys(self.NAMESPACE_PREFIX):
            # dirty_path contains unique prefix to prevent repeatable keys in the resource storage
            path = dirty_path.split(b'/', 1)[1]
            namespaces = __resource.find(key).split(b':')
            for n in namespaces:
                self.namespace_paths.setdefault(_s(n.rstrip(b'.')), set()).add(_s(path))

        # Populate module cache by namespace packages
        self.module_path_cache[''] = self.namespace_paths.get('', set())
        for package_name in self.namespace_paths:
            self._cache_module_path(package_name, find_package_only=True, force_package_exists=True)

    def get_module_path(self, fullname):
        """
            Find file path for module 'fullname'.
            For packages caller pass fullname as 'package.__init__'.
            Return None if nothing is found.
        """
        try:
            if not self.is_package(fullname):
                return _b(self._cache_module_path(fullname))
        except ImportError:
            pass

    def is_package(self, fullname):
        """Check if fullname is a package. Raise ImportError if fullname is not found"""
        path = self._cache_module_path(fullname)
        if isinstance(path, set):
            return True
        if isinstance(path, str):
            return False
        raise ImportError(fullname)

    def iter_modules(self, package_prefix, prefix):
        paths = self._cache_module_path(package_prefix.rstrip('.'))
        if paths is not None:
            # Note: it's ok to yield duplicates because pkgutil discards them

            # Yield from cache
            import re
            rx = re.compile(re.escape(package_prefix) + r'([^.]+)$')
            for p in self.module_path_cache.keys():
                m = rx.match(p)
                if m:
                    yield prefix + m.group(1), self.is_package(p)

            # Yield from file system
            for path in paths:
                abs_path = _path_join(self.source_root, path)
                for dir_item in _os.listdir(abs_path):
                    if _path_isdir(_path_join(abs_path, dir_item)):
                        yield prefix  +  dir_item, True
                    elif dir_item.endswith(self.PY_EXT) and _path_isfile(_path_join(abs_path, dir_item)):
                        yield prefix + dir_item[:-len(self.PY_EXT)], False

    def _cache_module_path(self, fullname, find_package_only=False, force_package_exists=False):
        """ 
            Find module path or package directory paths and save result in the cache

            find_package_only=True - don't try to find module
            force_package_exists=True - create 'virtual' packages for the namespace even if there is no underlying directory for fullname
        """
        if force_package_exists and not find_package_only:
            raise ValueError("find_package_only must be True if force_package_exists is True")
        if fullname in self.module_path_cache:
            return self.module_path_cache[fullname]
        package_paths = self.namespace_paths.get(fullname, set())
        parent, _, tail = fullname.rpartition('.')
        parent_paths = self._cache_module_path(parent, find_package_only=True, force_package_exists=force_package_exists)
        result = None
        if parent_paths:
            for path in parent_paths:
                file_path = _path_join(path, tail)
                if not find_package_only:
                    # Check if file_path is a module
                    module_path = file_path + self.PY_EXT
                    if _path_isfile(_path_join(self.source_root, module_path)):
                        result = module_path
                        break
                # Check if file_path is a package
                if _path_isdir(_path_join(self.source_root, file_path)):
                    package_paths.add(file_path)
        if not result and (package_paths or force_package_exists):
            result = package_paths
        self.module_path_cache[fullname] = result
        return result


def excepthook(*args, **kws):
    # traceback module cannot be imported at module level, because interpreter
    # is not fully initialized yet

    import traceback

    return traceback.print_exception(*args, **kws)


sys.meta_path.insert(0, BuiltinSubmoduleImporter)

importer = ResourceImporter()
sys.meta_path.insert(0, importer)


def executable_path_hook(path):
    if path == executable:
        return importer

    if path.startswith(executable + path_sep):
        return importer.for_package(path[len(executable + path_sep):].replace(path_sep, '.'))

    raise ImportError(path)


if executable not in sys.path:
    sys.path.insert(0, executable)
sys.path_hooks.insert(0, executable_path_hook)
sys.path_importer_cache[executable] = importer

# Indicator that modules and resources are built-in rather than on the file system.
sys.is_standalone_binary = True
sys.frozen = True

# Set of names of importable modules.
sys.extra_modules = importer.memory

# Use custom implementation of traceback printer.
# Built-in printer (PyTraceBack_Print) does not support custom module loaders
sys.excepthook = excepthook
