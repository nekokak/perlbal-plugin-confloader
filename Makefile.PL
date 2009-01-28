use inc::Module::Install;
name 'Perlbal-Plugin-ConfLoader';
all_from 'lib/Perlbal/Plugin/ConfLoader.pm';

build_requires 'Test::More';
build_requires 'Test::Declare';

use_test_base;
auto_include;
WriteAll;
