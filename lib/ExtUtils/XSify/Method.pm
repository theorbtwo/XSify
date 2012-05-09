package ExtUtils::XSify::Method;
use Moose;
use MooseX::StrictConstructor;

extends 'ExtUtils::XSify::FunctionDecl';

has 'access', is => 'ro';

'It is easier to destroy then to create';
