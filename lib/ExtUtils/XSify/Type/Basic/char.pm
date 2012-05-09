package ExtUtils::XSify::Type::Basic::char;
use Moose;
use MooseX::StrictConstructor;

extends 'ExtUtils::XSify::Type::Basic';

sub output_name {
  return 'char';
}

'char';
