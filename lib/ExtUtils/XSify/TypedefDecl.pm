package ExtUtils::XSify::TypedefDecl;
use Moose;
use MooseX::StrictConstructor;

has 'cursor',
  is => 'ro',
  required => 1;

sub to_do_mark {
  shift->cursor->getCursorUSR;
}

sub make_xs {
}

sub more_to_do {
}

'Would a rose by any other name smell so sweet?';
