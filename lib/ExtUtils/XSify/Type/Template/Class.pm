package ExtUtils::XSify::Type::Template::Class;
use Moose;
use MooseX::StrictConstructor;

has 'template',
  is => 'ro';

has 'parameters',
  is => 'ro';

sub output_name {
  my ($self) = @_;

  $self->template->output_name . "<" . join(", ", map {$_->output_name} @{$self->{parameters}}) . ">";
}

'Stiff upper lip, stiff upper lip';
