extends Node3D

enum PieceType { STANDARD, MINI, BARREL }

@export var piece_type: PieceType = PieceType.STANDARD


func piece_height() -> float:
	match piece_type:
		PieceType.MINI:
			return GameConstants.MINI_H
		PieceType.BARREL:
			return GameConstants.BARREL_H
		_:
			return GameConstants.STANDARD_H


func piece_extra() -> float:
	match piece_type:
		PieceType.MINI:
			return GameConstants.MINI_EXTRA
		PieceType.BARREL:
			return GameConstants.BARREL_EXTRA
		_:
			return GameConstants.STANDARD_EXTRA


func can_receive_nest() -> bool:
	return piece_type != PieceType.BARREL


func is_upright() -> bool:
	return global_basis.y.normalized().dot(Vector3.UP) >= GameConstants.UPRIGHT_DOT
