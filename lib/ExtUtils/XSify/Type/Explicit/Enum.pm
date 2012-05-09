package ExtUtils::XSify::Type::Explicit::Enum;
use Moose;
use MooseX::StrictConstructor;

extends 'ExtUtils::XSify::Type::Explicit';

sub more_to_do {
}

sub make_xs {
  my ($self) = @_;

  ExtUtils::XSify::Symbol::Function::dump_visit_tree($self->cursor);
  die;
}

'1, 2, 5';
