package ExtUtils::XSify::Type::Explicit::Typedef;
use Moose;
use MooseX::StrictConstructor;
use ExtUtils::XSify::TypedefDecl;

extends 'ExtUtils::XSify::Type::Explicit';

sub output_name {
  $_[0]->cursor->getCursorSpelling;
}

sub more_to_do {
  my ($self) = @_;

  ExtUtils::XSify::Symbol::Function::dump_visit_tree($self->cursor);
}

sub make_xs {
}

'Dracula, Dracul, Drac or just D.  Depends how well you know him.';
