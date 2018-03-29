meta:
  id: apfs
  license: MIT
  encoding: UTF-8
  endian: le

seq:
  - id: msb
    type: obj
    size: 4096
instances:
  block_size:
    value: msb.body.as<container_superblock>.block_size
  block_count:
    value: msb.body.as<container_superblock>.block_count
  blocks:
    pos: 0
    type: obj
    size: 4096
    repeat: expr
    repeat-expr: block_count  # '(block_count < 300 ? block_count : 300)'
#  random_block:
#    pos: 0 * msb.block_size # enter block number here to jump directly that block in the WebIDE
#    type: obj               # opens a sub stream for making positioning inside the block work
#    size: msb.block_size

types:

# block navigation

  ref_obj:
    doc: |
      Universal type to address a block: it both parses one u8-sized
      block address and provides a lazy instance to parse that block
      right away.
    seq:
      - id: value
        type: u8
    instances:
      target:
        io: _root._io
        pos: value * _root.block_size
        type: obj
        size: _root.block_size
    -webide-representation: 'Blk {value:dec}'

# meta structs

  obj_header:
    seq:
      - id: o_cksum
        type: u8
        doc: Flechters checksum, according to the docs.
      - id: o_oid
        type: u8
        doc: ID of the obj itself. Either the position of the obj or an incrementing number starting at 1024.
      - id: version
        type: u8
        doc: Incrementing number of the version of the obj (highest == latest)
      - id: o_type
        type: u2
        enum: obj_type
      - id: o_flags
        type: u2
        doc: 0x4000 oid = position, 0x8000 = container
      - id: o_subtype
        type: u2
        enum: obj_subtype
      - id: pad
        type: u2

  obj:
    seq:
      - id: hdr
        type: obj_header
      - id: body
        #size-eos: true
        type:
          switch-on: hdr.o_type
          cases:
            obj_type::container_superblock: container_superblock
            obj_type::rootnode: node
            obj_type::node: node
            obj_type::space_manager: space_manager
            obj_type::allocationinfofile: allocationinfofile
            obj_type::btree: btree
            obj_type::checkpoint: checkpoint
            obj_type::volume_superblock: volume_superblock
    -webide-representation: '{hdr.o_type} ({hdr.o_subtype})'
            

# container_superblock (type: 0x01)

  container_superblock:
    seq:
      - id: magic
        size: 4
        contents: [NXSB]
      - id: block_size
        type: u4
      - id: block_count
        type: u8
      - id: pad
        size: 16
      - id: unknown_64
        type: u8
      - id: guid
        size: 16
      - id: next_oid
        type: u8
      - id: next_version
        type: u8
      - id: unknown_104
        type: u4
      - id: unknown_108
        type: u4
      - id: superblock_area_start
        type: u8
      - id: spaceman_area_start
        type: u8
      - id: next_superblock_from_area_start
        type: u4
      - id: next_spaceman_from_area_start
        type: u4
      - id: current_superblock_from_area_start
        type: u4
      - id: current_superblock_length
        type: u4
      - id: current_spaceman_from_area_start
        type: u4
      - id: current_spaceman_length
        type: u4
      - id: space_manager_id
        type: u8
      - id: object_map_block
        type: ref_obj
      - id: unknown_168_id
        type: u8
      - id: pad2
        type: u4
      - id: volume_superblock_id_count
        type: u4
      - id: volume_superblock_ids
        type: u8
        repeat: expr
        repeat-expr: volume_superblock_id_count

# node (type: 0x02)

  node:
    seq:
      - id: node_type
        type: u2
      - id: level
        type: u2
        doc: Zero for leaf nodes, > 0 for branch nodes
      - id: entry_count
        type: u4
      - id: unknown_40
        type: u2
      - id: keys_offset
        type: u2
      - id: keys_length
        type: u2
      - id: data_offset
        type: u2
      - id: meta_entry
        type: full_entry_header
      - id: entries
        type: node_entry
        repeat: expr
        repeat-expr: entry_count
    instances:
      footer:
        pos: _root.block_size - 40
        type: node_footer
        if: (node_type & 1) != 0

  full_entry_header:
    seq:
      - id: key_offset
        type: s2
      - id: key_length
        type: u2
      - id: data_offset
        type: s2
      - id: data_length
        type: u2

  dynamic_entry_header:
    seq:
      - id: key_offset
        type: s2
      - id: key_length
        type: u2
        if: has_lengths
      - id: data_offset
        type: s2
      - id: data_length
        type: u2
        if: has_lengths
    instances:
      has_lengths:
        value: (_parent._parent.node_type & 4) == 0

  node_footer:
    seq:
      - id: unknown_0
        type: u4
      - id: unknown_4
        type: u4
      - id: key_length
        type: u4
      - id: data_length
        type: u4
      - id: max_key_length
        type: u4
      - id: max_data_length
        type: u4
      - id: total_entry_count_for_branch
        type: u8
      - id: next_record_number
        type: u8

## node entries

  node_entry:
    seq:
      - id: header
        type: dynamic_entry_header
    instances:
      key:
        pos: header.key_offset + _parent.keys_offset + 56
        #TODO: Still missing fallback for when there is no footer.
        size: 'header.has_lengths ? header.key_length : _parent.footer.key_length'
        type:
          switch-on: '(((_parent.node_type & 2) == 0) ? 256 : 0) + _parent._parent.hdr.o_subtype.to_i * (((_parent.node_type & 2) == 0) ? 0 : 1)'
          cases:
            obj_subtype::history.to_i: history_key
            obj_subtype::location.to_i: location_key
            obj_subtype::files.to_i: file_key
        -webide-parse-mode: eager
      val:
        pos: _root.block_size - header.data_offset - 40 * (_parent.node_type & 1)
        #TODO: Still missing fallback for when there is no footer.
        size: 'header.has_lengths ? header.data_length : _parent.footer.data_length'
        type:
          switch-on: '((_parent.node_type & 2) == 0) ? 256 : _parent._parent.hdr.o_subtype.to_i'
          cases:
            256: pointer_record # applies to all pointer records, i.e. any entry val in index nodes
            obj_subtype::location.to_i: location_record
            obj_subtype::history.to_i: history_record
            obj_subtype::files.to_i: file_record
        -webide-parse-mode: eager
    -webide-representation: '{key}: {val}'

## node entry keys

  file_key:
    seq:
      - id: key_low # this is a work-around for JavaScript's inability to hande 64 bit values
        type: u4
      - id: key_high
        type: u4
      - id: content
        size: _parent.header.key_length - 8
        type:
          switch-on: record_type
          cases:
            record_type::direntry: named_key
            record_type::inode: inode_key
            record_type::basicattr: basic_key
            record_type::entry6: basic_key
            record_type::hardlink: hardlink_key
            record_type::hardlinkback: basic_key
            record_type::extattr: named_key
            record_type::extent: extent_key
    instances:
      node_id:
        value: key_low + ((key_high & 0x0FFFFFFF) << 32)
        -webide-parse-mode: eager
      record_type:
        value: key_high >> 28
        enum: record_type
        -webide-parse-mode: eager
    -webide-representation: '({record_type}) {node_id:dec} {content}'

  basic_key:
    -webide-representation: ''

  file_record:
    instances:
      value:
        type:
          switch-on: _parent.key.as<file_key>.record_type
          cases:
            record_type::direntry: direntry_record
            record_type::inode: inode_record
            record_type::basicattr: basicattr_record
            record_type::hardlink: hardlink_record
            record_type::entry6: t6_record
            record_type::extent: extent_record
            record_type::hardlinkback: hardlinkback_record
            record_type::extattr: extattr_record
        size-eos: true
        -webide-parse-mode: eager
    -webide-representation: '{value}'

  location_key:
    seq:
      - id: oid
        type: u8
      - id: version
        type: u8
    -webide-representation: 'ID {oid:dec} v{version:dec}'

  history_key:
    seq:
      - id: version
        type: u8
      - id: obj_id
        type: ref_obj
    -webide-representation: '{obj_id} v{version:dec}'

  inode_key:
    seq:
      - id: obj_id
        type: ref_obj
    -webide-representation: '{obj_id}'

  named_key:
    seq:
      - id: name_length
        type: u1
      - id: second_byte
        type: u1
    instances:
      hash:
        type: u4
        pos: 0
        # TODO Technically you're supposed to look at the volume header,
        #      so this condition will occasionally be wrong.
        if: second_byte != 0
      dirname:
        pos: 'second_byte != 0 ? 4 : 2'
        size: name_length
        type: strz
    -webide-representation: '"{dirname}"'

  hardlink_key:
    seq:
      - id: id2
        type: u8
    -webide-representation: '#{id2:dec}'

  extent_key:
    seq:
      - id: offset # seek pos in file
        type: u8
    -webide-representation: '{offset:dec}'

## node entry records

  pointer_record: # for any index nodes
    seq:
      - id: pointer
        type: u8
    -webide-representation: '-> {pointer:dec}'

  history_record:
    seq:
      - id: unknown_0
        type: u4
      - id: unknown_4
        type: u4
    -webide-representation: '{unknown_0}, {unknown_4}'

  location_record: # 0x00
    seq:
      - id: block_start
        type: u4
      - id: block_length
        type: u4
      - id: obj_id
        type: ref_obj
    -webide-representation: '{obj_id}, from {block_start:dec}, len {block_length:dec}'

  basicattr_record: # 0x30
    seq:
      - id: parent_id
        type: u8
      - id: node_id
        type: u8
      - id: creation_timestamp
        type: u8
      - id: modified_timestamp
        type: u8
      - id: changed_timestamp
        type: u8
      - id: accessed_timestamp
        type: u8
      - id: flags
        type: u8
      - id: nchildren_or_nlink
        type: u4
      - id: unknown_60
        type: u4
      - id: unknown_64
        type: u4
      - id: bsdflags
        type: u4
      - id: owner_id
        type: u4
      - id: group_id
        type: u4
      - id: mode
        type: u2
      - id: unknown_82
        type: u2
      - id: unknown_84
        type: u4
      - id: unknown_88
        type: u4
      - id: filler_flag
        type: u2
      - id: unknown_94
        type: u2
      - id: unknown_96
        type: u2
      - id: name_length
        type: u2
      - id: name_filler_1
        type: u4
        if: filler_flag >= 2
      - id: name_filler_2
        type: u4
        if: filler_flag >= 3
      - id: name
        type: strz
      - id: unknown_remainder
        size-eos: true
    -webide-representation: '#{node_id:dec} / #{parent_id:dec} "{name}"'

  hardlink_record: # 0x50
    seq:
      - id: node_id
        type: u8
      - id: namelength
        type: u2
      - id: dirname
        size: namelength
        type: str
    -webide-representation: '#{node_id:dec} "{dirname}"'

  t6_record: # 0x60
    seq:
      - id: unknown_0    #TODO: seems to contain 0x1 always, and the record is only present for non-empty files.
        type: u4
    -webide-representation: '{unknown_0}'

  inode_record: # 0x20
    seq:
      - id: block_count
        type: u4
      - id: unknown_4
        type: u2
      - id: block_size
        type: u2
      - id: inode
        type: u8
      - id: unknown_16
        type: u4
    -webide-representation: '#{inode:dec}, Cnt {block_count:dec} * {block_size:dec}, {unknown_4:dec}, {unknown_16:dec}'
  
  extent_record: # 0x80
    seq:
      - id: size
        type: u8
      - id: obj_id
        type: ref_obj
      - id: unknown_16
        type: u8
    -webide-representation: '{obj_id}, Len {size:dec}, {unknown_16:dec}'

  direntry_record: # 0x90
    seq:
      - id: node_id
        type: u8
      - id: timestamp
        type: u8
      - id: item_type
        type: u2
        enum: item_type
    -webide-representation: '#{node_id:dec}, {item_type}'

  hardlinkback_record: # 0xc0
    seq:
      - id: node_id
        type: u8
    -webide-representation: '#{node_id:dec}'

  extattr_record: # 0x40
    seq:
      - id: ea_type
        type: u2
        enum: ea_type
      - id: data_length
        type: u2
      - id: data
        size: data_length
        type:
          switch-on: ea_type
          cases:
            ea_type::symlink: strz # symlink
            # all remaining cases are handled as a "bunch of bytes", thanks to the "size" argument
    -webide-representation: '{ea_type} {data}'


# space_manager (type: 0x05)

  space_manager:
    seq:
      - id: block_size
        type: u4
      - id: unknown_36
        size: 12
      - id: block_count
        type: u8
      - id: unknown_56
        size: 8
      - id: entry_count
        type: u4
      - id: unknown_68
        type: u4
      - id: free_block_count
        type: u8
      - id: entries_offset
        type: u4
      - id: unknown_84
        size: 92
      - id: prev_allocationinfofile_block
        type: u8
      - id: unknown_184
        size: 200
    instances:
      allocationinfofile_blocks:
        pos: entries_offset
        repeat: expr
        repeat-expr: entry_count
        type: u8

# allocation info file (type: 0x07)

  allocationinfofile:
    seq:
      - id: unknown_32
        size: 4
      - id: entry_count
        type: u4
      - id: entries
        type: allocationinfofile_entry
        repeat: expr
        repeat-expr: entry_count

  allocationinfofile_entry:
    seq:
      - id: version
        type: u8
      - id: unknown_8
        type: u4
      - id: unknown_12
        type: u4
      - id: block_count
        type: u4
      - id: free_block_count
        type: u4
      - id: allocationfile_block
        type: u8

# btree (type: 0x0b)

  btree:
    seq:
      - id: unknown_0
        size: 16
      - id: root
        type: ref_obj

# checkpoint (type: 0x0c)

  checkpoint:
    seq:
      - id: unknown_0
        type: u4
      - id: entry_count
        type: u4
      - id: entries
        type: checkpoint_entry
        repeat: expr
        repeat-expr: entry_count

  checkpoint_entry:
    seq:
      - id: o_type
        type: u2
        enum: obj_type
      - id: flags
        type: u2
      - id: obj_subtype
        type: u4
        enum: obj_subtype
      - id: block_size
        type: u4
      - id: unknown_52
        type: u4
      - id: unknown_56
        type: u4
      - id: unknown_60
        type: u4
      - id: oid
        type: u8
      - id: object
        type: ref_obj

# volume_superblock (type: 0x0d)

  volume_superblock:
    seq:
      - id: magic
        size: 4
        contents: [APSB]
      - id: unknown_36
        size: 92
      - id: object_map_block
        type: ref_obj
        doc: 'Maps node IDs to the inode Btree nodes'
      - id: root_dir_id
        type: u8
      - id: inode_map_block
        type: ref_obj
        doc: 'Maps file extents to inodes'
      - id: unknown_152_blk
        type: ref_obj
      - id: unknown_160
        size: 16
      - id: next_catalog_node_id
        type: u8
      - id: total_file_count
        type: u8
      - id: total_folder_count
        type: u8
      - id: unknown_200
        size: 40
      - id: volume_guid
        size: 16
      - id: time_updated
        type: u8
      - id: unknown_264
        type: u8
      - id: access_history
        type: volume_access_info
        repeat: expr
        repeat-expr: 9
      - id: volume_name
        type: strz

  volume_access_info:
    seq:
      - id: accessed_by
        size: 32
        type: strz
      - id: time_accessed
        type: u8
      - id: version
        type: u8

# enums

enums:

  obj_type:
    1: container_superblock
    2: rootnode
    3: node
    5: space_manager
    7: allocationinfofile
    11: btree
    12: checkpoint
    13: volume_superblock
    17: unknown

  record_type:
    0x0: location
    0x2: inode
    0x3: basicattr
    0x4: extattr
    0x5: hardlink
    0x6: entry6
    0x8: extent
    0x9: direntry
    0xc: hardlinkback

  obj_subtype:
    0: empty
    9: history
    11: location
    14: files
    15: extents
    16: unknown3

  item_type:
    4: folder
    8: file
    10: symlink

  ea_type:
    2: generic
    6: symlink
