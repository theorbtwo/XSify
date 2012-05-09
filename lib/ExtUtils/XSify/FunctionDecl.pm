package ExtUtils::XSify::FunctionDecl;
use Moose;
use MooseX::StrictConstructor;
use 5.10.0;

use ExtUtils::XSify::Type;
use ExtUtils::XSify::Type::Template;

extends 'ExtUtils::XSify::SymbolDecl';

# FIXME: Where does this belong?
sub dump_visit_tree {
  my ($cursor, $depth) = @_;
  $depth ||= 0;
  my $indent = ' ' x $depth;
  
  my $spelling = $cursor->getCursorSpelling;
  if ($spelling) {
    $spelling = " [sp: '$spelling']";
  } else {
    $spelling = '';
  }

  print $indent.$cursor->getCursorKind.$spelling."\n";

  $cursor->visitChildren(sub {
                           dump_visit_tree(shift, $depth+1);
                           return 1;
                         });
}

sub return_type {
  my ($self) = @_;

  my $type = $self->cursor->getCursorResultType;
  return ExtUtils::XSify::Type->new(type => $type,
                                    location => $self->location,
                                    parent_cursor => $self->cursor);
}

sub args {
  my ($self) = @_;

  my @args;

  $self->cursor->visitChildren
    (sub {
       my ($cursor, $parent_cursor) = @_;

       my $kind = $cursor->getCursorKind;

       given ($kind) {
         when (10) {
           # ParmDecl
           my $name = $cursor->getCursorSpelling;

           my $type = ExtUtils::XSify::Type->new(type => $cursor->getCursorType,
                                                 location => $self->location . " argument named $name",
                                                 parent_cursor => $cursor,
                                                );

           push @args, {name => $name, type => $type};
         }

         when (43) {
           # TypeRef - I'm not sure what it is, but it isn't a parameter...
           #CV_INLINE CvRNG cvRNG( int64 seed CV_DEFAULT(-1)) {...}
           return 1;
         }

         when (45) {
           # TemplateRef
           #   template<typename _ForwardIterator, typename _Tp>
           #     _Temporary_buffer<_ForwardIterator, _Tp>::
           #     _Temporary_buffer(_ForwardIterator __first, _ForwardIterator __last)
           #     : _M_original_len(std::distance(__first, __last)),
           #       _M_len(0), _M_buffer(0) {...}
           return 1;
         }

         when (46) {
           # NamespaceRef
           # template<typename _CharT> std::size_t char_traits<_CharT>::length() {...}
           return 1;
         }

         when (47) {
           # MemberRef
           #  - I think this means that we've reached the designated initializer, which
           #    means we're past the arguments.
           return 0;
         }

         when ([100..199]) {
           # Expressions
           return 1;
         }

         when (202) {
           # CompoundStmt
           # We've reached the function body.
           return 0;
         }

         when (400) {
           # UnexposedAttr
           return 1;
         }

         default {
           die "In args of function, don't know what to do with kind $kind";
         }
       }
     });

  return @args;
}

sub make_xs {
  my ($self, $xs, $pm, $typemap) = @_;

  return if $self->unsupported;

  my $module = $self->perl_module;

  my ($return_type_c, $retval_eq, $output_section);
  if ($self->return_type) {
    $return_type_c = $self->return_type->output_name;
    $retval_eq = 'RETVAL = ';
    $output_section = " OUTPUT:\n  RETVAL";
  } else {
    $return_type_c = 'void';
    $retval_eq = '';
    $output_section = "";
  }

  my $short_c_name = $self->short_c_name;

  my $extended_name = $self->extended_name;

  my @args = $self->args;

  my $arg_list_decl = join(', ', map { $_->{type}->output_name . " $_->{name}"} @args);
  my $arg_list_use = join(', ', map { "$_->{name}" } @args);

  my $text = <<END;
$return_type_c
$extended_name($arg_list_decl)
 CODE:
  $retval_eq $short_c_name($arg_list_use);
$output_section
END

  push @{$xs->{$module}}, $text;
}

sub more_to_do {
  my ($self) = @_;

  return if $self->unsupported;

  if ($self->return_type) {
    return ($self->return_type,
            map {$_->{type}} $self->args);
  }

  return map {$_->{type}} $self->args;
}

"functions that take functions that write functions are the happiest functions of them all";
