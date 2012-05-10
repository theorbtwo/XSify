package ExtUtils::XSify::Type::Basic::float;
use Moose;
use MooseX::StrictConstructor;

extends 'ExtUtils::XSify::Type::Basic';

sub output_name {
  return 'float';
}

'float';
