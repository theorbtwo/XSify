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

sub to_do_mark {
  my ($self) = @_;

  $self->template->to_do_mark . '<' . join(',', map {$_->to_do_mark} @{$self->parameters}) . '>';
}

sub more_to_do {
  my ($self) = @_;

  # Should I give the template here as well?  The full
  # kit-and-kaboodle of contents of the template, properly qualified?
  @{$self->{parameters}};
}

sub make_xs {
  my ($self, $xs, $pm, $typemap) = @_;
}

'Stiff upper lip, stiff upper lip';
