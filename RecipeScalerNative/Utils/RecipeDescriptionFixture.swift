//
//  RecipeDescriptionFixture.swift
//  RecipeScalerNative
//
//  Reference HTML for description UI verification (matches Tiptap output shape).
//

import Foundation

enum RecipeDescriptionFixture {
    /// All supported block/inline elements for simulator checks (`-ShowDescriptionFixture`).
    static let allElementsHTML: String = """
    <p>Intro with <a href="https://recipe-scaler.ru/mcp" target="_blank" rel="noopener noreferrer">recipe-scaler.ru/mcp</a> link.</p>
    <ol>
    <li><p>Step one: add <span class="ingredient-reference" data-ingredient-id="fixture-flour" data-ratio="1">250 g flour</span> and salt.</p></li>
    <li><p>Step two: bake <span class="timer-reference" data-duration="1800" data-type="minutes" data-name="Bake" data-value="30">30 minutes</span> at 180°C.</p></li>
    <li><p>Step three with <strong>bold</strong> and <em>italic</em> text.</p></li>
    </ol>
    <p>Paragraph after the list with a line break<br/>on the next line.</p>
    <ul>
    <li><p>Bullet one</p></li>
    <li><p>Bullet two</p></li>
    </ul>
    <h1>Section heading</h1>
    <p>Final paragraph.</p>
    """

    static var showsPreview: Bool {
        ProcessInfo.processInfo.arguments.contains("-ShowDescriptionFixture")
    }
}