package ExtUtils::XSify::Enum;
use Moose;
use MooseX::StrictConstructor;

has 'cursor', is => 'ro';
has 'access', is => 'ro';

sub to_do_mark {
  shift->cursor->getCursorUSR;
}

'1, 2, 5';
