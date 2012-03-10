package CLang;
use warnings;
use strict;

our $VERSION = '0.001';

require DynaLoader;
our @ISA = qw(DynaLoader);

__PACKAGE__->bootstrap;

sub CLang::Index::DESTROY {
  shift->disposeIndex;
}

sub CLang::TranslationUnit::DESTROY {
  shift->disposeTranslationUnit;
}

package CLang::String {
  use overload '""' => \&stringify;

  sub DESTROY {
    shift->disposeString;
  }

  sub stringify {
    shift->getCString;
  }
};



'Fixme: Need something interesting here';
