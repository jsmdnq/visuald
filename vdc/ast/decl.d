// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module vdc.ast.decl;

import vdc.util;
import vdc.lexer;
import vdc.semantic;
import vdc.interpret;

import vdc.ast.node;
import vdc.ast.expr;
import vdc.ast.misc;
import vdc.ast.aggr;
import vdc.ast.tmpl;
import vdc.ast.stmt;
import vdc.ast.type;
import vdc.ast.mod;

import std.conv;

//Declaration:
//    alias Decl
//    Decl
class Declaration : Node
{
	mixin ForwardCtor!();
}

// AliasDeclaration:
//    [Decl]
class AliasDeclaration : Node
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		if(writer.writeDeclarations)
			writer("alias ", getMember(0));
	}
	void addSymbols(Scope sc)
	{
		getMember(0).addSymbols(sc);
	}
}

//Decl:
//    attributes annotations [Type Declarators FunctionBody_opt]
class Decl : Node
{
	mixin ForwardCtor!();

	bool hasSemi;
	bool isAlias;
	
	Type getType() { return getMember!Type(0); }
	Declarators getDeclarators() { return getMember!Declarators(1); }
	FunctionBody getFunctionBody() { return getMember!FunctionBody(2); }
	
	Decl clone()
	{
		Decl n = static_cast!Decl(super.clone());
		n.hasSemi = hasSemi;
		n.isAlias = isAlias;
		return n;
	}
	
	bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.hasSemi == hasSemi
			&& tn.isAlias == isAlias;
	}

	void toD(CodeWriter writer)
	{
		if(isAlias)
			writer(TOK_alias, " ");
		writer.writeAttributes(attr);
		writer.writeAnnotations(annotation);
		
		writer(getType(), " ", getDeclarators());
		bool semi = true;
		if(auto fn = getFunctionBody())
		{
			if(writer.writeImplementations)
			{
				writer.nl;
				writer(fn);
				semi = hasSemi;
			}
		}
		if(semi)
		{
			writer(";");
			writer.nl();
		}
	}

	void toC(CodeWriter writer)
	{
		bool addExtern = false;
		if(!isAlias && writer.writeDeclarations && !(attr & Attr_ExternC))
		{
			Node p = parent;
			while(p && !cast(Aggregate) p && !cast(TemplateDeclaration) p && !cast(Statement) p)
				p = p.parent;
			
			if(!p)
				addExtern = true;
		}
		if(auto fn = getFunctionBody())
		{
			if(writer.writeReferencedOnly && getDeclarators().getDeclarator(0).semanticSearches == 0)
				return;
				
			writer.nl;
			if(isAlias)
				writer(TOK_alias, " ");
			writer.writeAttributes(attr | (addExtern ? Attr_Extern : 0));
			writer.writeAnnotations(annotation);
			
			bool semi = true;
			writer(getType(), " ", getDeclarators());
			if(writer.writeImplementations)
			{
				writer.nl;
				writer(fn);
				semi = hasSemi;
			}
			if(semi)
			{
				writer(";");
				writer.nl();
			}
		}
		else
		{
			foreach(i, d; getDeclarators().members)
			{
				if(writer.writeReferencedOnly && getDeclarators().getDeclarator(i).semanticSearches == 0)
					continue;
				
				if(isAlias)
					writer(TOK_alias, " ");
				writer.writeAttributes(attr | (addExtern ? Attr_Extern : 0));
				writer.writeAnnotations(annotation);
				
				writer(getType(), " ", d, ";");
				writer.nl();
			}
		}
	}
	
	void addSymbols(Scope sc)
	{
		getDeclarators().addSymbols(sc);
	}
}

//Declarators:
//    [DeclaratorInitializer|Declarator...]
class Declarators : Node
{
	mixin ForwardCtor!();

	Declarator getDeclarator(int n)
	{
		if(auto decl = cast(Declarator) getMember(n))
			return decl;

		return getMember!DeclaratorInitializer(n).getDeclarator();
	}
	
	void toD(CodeWriter writer)
	{
		writer(getMember(0));
		foreach(decl; members[1..$])
			writer(", ", decl);
	}
	void addSymbols(Scope sc)
	{
		foreach(decl; members)
			decl.addSymbols(sc);
	}
}

//DeclaratorInitializer:
//    [Declarator Initializer_opt]
class DeclaratorInitializer : Node
{
	mixin ForwardCtor!();
	
	Declarator getDeclarator() { return getMember!Declarator(0); }
	Expression getInitializer() { return getMember!Expression(1); }

	void toD(CodeWriter writer)
	{
		writer(getMember(0));
		if(Expression expr = getInitializer())
		{
			if(expr.getPrecedence() <= PREC.assign)
				writer(" = (", expr, ")");
			else
				writer(" = ", getMember(1));
		}
	}

	void addSymbols(Scope sc)
	{
		getDeclarator().addSymbols(sc);
	}
}

// unused
class DeclaratorIdentifierList : Node
{
	mixin ForwardCtor!();
	
	void toD(CodeWriter writer)
	{
		assert(false);
	}
}

// unused
class DeclaratorIdentifier : Node
{
	mixin ForwardCtor!();
	
	void toD(CodeWriter writer)
	{
		assert(false);
	}
}

class Initializer : Expression
{
	mixin ForwardCtor!();
}

//Declarator:
//    Identifier [DeclaratorSuffixes...]
class Declarator : Identifier
{
	mixin ForwardCtorTok!();

	void toD(CodeWriter writer)
	{
		super.toD(writer);
		foreach(m; members) // template parameters and function parameters and constraint
			writer(m);
	}

	void addSymbols(Scope sc)
	{
		sc.addSymbol(ident, this);
	}
}

//IdentifierList:
//    [IdentifierOrTemplateInstance...]
class IdentifierList : Node
{
	mixin ForwardCtor!();

	bool global;
	
	// semantic data
	Node resolved;
	
	IdentifierList clone()
	{
		IdentifierList n = static_cast!IdentifierList(super.clone());
		n.global = global;
		return n;
	}
	
	bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.global == global;
	}
	
	void semantic(Scope sc)
	{
		if(global)
			sc = Module.getModule(this).scop;

		for(int m = 0; sc && m < members.length; m++)
		{
			string ident = getMember!Identifier(m).ident;
			resolved = sc.resolve(ident, span);
			sc = (resolved ? resolved.scop : null);
		}
	}
	
	void toD(CodeWriter writer)
	{
		if(global)
			writer(".");
		writer.writeArray(members, ".");
	}
}

class Identifier : Node
{
	string ident;
	
	this() {} // default constructor need for clone()

	this(Token tok)
	{
		super(tok);
		ident = tok.txt;
	}
	
	Identifier clone()
	{
		Identifier n = static_cast!Identifier(super.clone());
		n.ident = ident;
		return n;
	}

	bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.ident == ident;
	}
	
	void toD(CodeWriter writer)
	{
		writer.writeIdentifier(ident);
	}
}

//ParameterList:
//    [Parameter...] attributes
class ParameterList : Node
{
	mixin ForwardCtor!();

	Parameter getParameter(int i) { return getMember!Parameter(i); }
		
	bool varargs;
	
	ParameterList clone()
	{
		ParameterList n = static_cast!ParameterList(super.clone());
		n.varargs = varargs;
		return n;
	}

	bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.varargs == varargs;
	}
	
	void toD(CodeWriter writer)
	{
		writer("(");
		writer.writeArray(members);
		if(varargs)
			writer("...");
		writer(")");
		if(attr)
		{
			writer(" ");
			writer.writeAttributes(attr);
		}
	}
	
}

//Parameter:
//    io [ParameterDeclarator Expression_opt]
class Parameter : Node
{
	mixin ForwardCtor!();

	TokenId io;
	
	ParameterDeclarator getParameterDeclarator() { return getMember!ParameterDeclarator(0); }
	
	Parameter clone()
	{
		Parameter n = static_cast!Parameter(super.clone());
		n.io = io;
		return n;
	}

	bool compare(const(Node) n) const
	{
		if(!super.compare(n))
			return false;

		auto tn = static_cast!(typeof(this))(n);
		return tn.io == io;
	}
	
	void toD(CodeWriter writer)
	{
		if(io)
			writer(io, " ");
		writer(getMember(0));
		if(members.length > 1)
			writer(" = ", getMember(1));
	}
}

//ParameterDeclarator:
//    attributes [Type Declarator]
class ParameterDeclarator : Node
{
	mixin ForwardCtor!();

	Type getType() { return getMember!Type(0); }
	Declarator getDeclarator() { return members.length > 1 ? getMember!Declarator(1) : null; }
	
	void toD(CodeWriter writer)
	{
		writer.writeAttributes(attr);
		writer(getType());
		if(auto decl = getDeclarator())
			writer(" ", decl);
	}
}