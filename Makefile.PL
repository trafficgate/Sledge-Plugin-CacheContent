use ExtUtils::MakeMaker;
WriteMakefile(
    'NAME'      => 'Sledge::Plugin::CacheContent',
    'VERSION_FROM' => 'lib/Sledge/Plugin/CacheContent.pm', # finds $VERSION
    'PREREQ_PM' => {
	Test::More => 0.32,
    },
);
