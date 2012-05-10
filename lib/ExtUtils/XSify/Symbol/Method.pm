package ExtUtils::XSify::Symbol::Method;
use Moose;
use MooseX::StrictConstructor;

extends 'ExtUtils::XSify::Symbol::Function';

has 'access', is => 'ro';

sub invocant {
  'SELF.';
}

sub self_arg_list_decl {
  my ($self) = @_;
  my $class = ExtUtils::XSify::Type->factory(type => $self->cursor->getCursorSemanticParent->getCursorType,
                                             location => 'containing class of '.$self->location,
                                             parent_cursor => $self->cursor,
                                            );
  
  $class->output_name." SELF, ";
}

'It is easier to destroy then to create';
